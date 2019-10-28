
#include "methodOf4RusBooleanSemiringGpu.h"
#include <cuda_runtime_api.h>
#include <device_launch_parameters.h>
#include <device_types.h>

#define lsb(i) ((i) & -(i)) // return least significant bit

namespace gpu_m4ri {

__device__ bool is_changed_matrix = false;

__device__ size_t result = 0;

__global__ void sum_impl(const TYPE *d_data, size_t size) {
  if (blockIdx.x > 0)
    return;

  auto threads_per_block = blockDim.x;

  const auto threadId = threadIdx.x;
  extern __shared__ size_t s_data[];

  size_t thread_result = 0;
  for (size_t i = threadId; i < size; i += threads_per_block) {
    thread_result += __popc(d_data[i]);
  }

  s_data[threadId] = thread_result;
  __syncthreads();

  if (threadId == 0) {
    result = 0;
    for (size_t i = 0; i < threads_per_block; i++) {
      result += s_data[i];
    }
  }
}

size_t sum(const TYPE *d_data, size_t size) {
  size_t res;
  sum_impl<<<1, 512, 512 * sizeof(size_t)>>>(d_data, size);
  cudaMemcpyFromSymbol(&res, result, sizeof(size_t), 0, cudaMemcpyDeviceToHost);
  return res;
}

// return the next number with the same number of bits
__device__ int snoob(int i) {
  int least = lsb(i);
  int ripple = i + least;
  return (((ripple ^ i) >> 2) / least) | ripple;
}

__global__ void make_table_kernel_semiring(TYPE *B, TYPE **lookup_tables,
                                           int cols, int rows, int tables_num,
                                           int real_cols, int offset) {
  int x_col = blockIdx.x * BLOCK_SIZE_COL + threadIdx.x;
  int y_row = (blockIdx.y * BLOCK_SIZE_ROW + threadIdx.y) * K;
  int twokey = (1 << K);
  int i;
  int least, rest;

  if (x_col >= cols || y_row >= rows) {
    // if thread out of current computed part of the table then return
    return;
  }

  // pointer to calculated  table  Br
  TYPE *T = lookup_tables[blockIdx.y * BLOCK_SIZE_ROW + threadIdx.y];

  T[x_col] = 0; // row with 000000000...

// fill when table when 1 bit
#pragma unroll
  for (int j = 0; j < K; j++) {
    i = 1 << (j);
    T[i * cols + x_col] = B[(y_row + j) * real_cols + x_col + offset];
  }

#pragma unroll
  for (int h = 2; h <= K; h++) {
    // fill table elems with h bits in index and <2^K
    // idea taken from Peter Schäfer implementation for m4ri library
    i = (1 << h) - 1;
    for (; i < twokey; i = snoob(i)) {
      least = lsb(i);
      rest = i - least;
      T[i * cols + x_col] = T[least * cols + x_col] | T[rest * cols + x_col];
    }
  }
}

__device__ int get_actual_key(TYPE composite_key, int j) {
  return (0xFF) & (composite_key >> (8 * j));
}

__global__ void m4ri_mul_kernel_semiring(TYPE *A, TYPE *C, TYPE **lookup_tables,
                                         int rows, int cols, int cols_table,
                                         int offset) {
  __shared__ TYPE local_A[BLOCK_SIZE_ROW][BLOCK_SIZE_COL];
  int col_x = threadIdx.x + blockIdx.x * BLOCK_SIZE_COL + offset;
  int row_y = threadIdx.y + blockIdx.y * BLOCK_SIZE_ROW;
  int col_in_T = threadIdx.x + blockIdx.x * BLOCK_SIZE_COL;
  int full_steps = cols / BLOCK_SIZE_COL;
  int small_step = cols % BLOCK_SIZE_COL;
  TYPE *T;
  TYPE composite_key;
  int actual_key;
  TYPE old_c;

  if (col_x < cols && col_in_T < cols_table && row_y < rows) {
    // if not out
    old_c = C[row_y * cols + col_x];
  } else {
    old_c = 0;
  }

  TYPE tmp;
  TYPE value = 0;

#pragma unroll
  for (int i = 0; i < full_steps; i++) {
    // all complete runs
    tmp = __brev(A[row_y * cols + threadIdx.x + i * BLOCK_SIZE_COL]); // reverse
    local_A[threadIdx.y][threadIdx.x] = tmp;
    __syncthreads();

    for (int t = 0; t < BLOCK_SIZE_COL; t++) {
      composite_key = local_A[threadIdx.y][t];
      for (int j = 0; j < 4; j++) {
        T = lookup_tables[BLOCK_SIZE_COL * i * 4 + t * 4 + j];
        actual_key = get_actual_key(composite_key, j);
        value |= T[actual_key * cols_table + col_in_T];
      }
    }
  }
  __syncthreads();
  if (small_step) {
    int cur_step = full_steps;
    if (threadIdx.x + cur_step * BLOCK_SIZE_COL < cols && row_y < rows) {
      tmp = __brev(
          A[row_y * cols + threadIdx.x + cur_step * BLOCK_SIZE_COL]); // reverse
      local_A[threadIdx.y][threadIdx.x] = tmp;
    }
    __syncthreads();

    if (col_x >= cols || col_in_T >= cols_table || row_y >= rows) {
      // threads that out of current part of C contributed to all threads(load
      // keys) and can return
      return;
    }

    for (int t = 0; t < small_step; t++) {
      composite_key = local_A[threadIdx.y][t];
      for (int j = 0; j < 4; j++) {
        T = lookup_tables[cur_step * BLOCK_SIZE_COL * 4 + t * 4 + j];
        actual_key = get_actual_key(composite_key, j);
        value |= T[actual_key * cols_table + col_in_T];
      }
    }
  }
  value = value | old_c;

  if (is_changed_matrix == false && value != old_c) {
    is_changed_matrix = true;
  }

  if (col_x < cols && row_y < rows && col_in_T < cols_table && value != old_c) {
    C[row_y * cols + col_x] = old_c | value;
  }
}

int wrapper_method_of_4rus_bool_semiring(TYPE *a, TYPE *b, TYPE *c,
                                         Tables &tables, int rows, int cols) {
  int is_c_changed = false;
  cudaMemcpyToSymbol(is_changed_matrix, &is_c_changed, sizeof(bool), 0,
                     cudaMemcpyHostToDevice);

  // setup configuration for table kernel
  dim3 dimBlock_table_kernel(BLOCK_SIZE_COL, BLOCK_SIZE_ROW);

  dim3 dimGrid_table_n((tables.cols_n + BLOCK_SIZE_COL - 1) / BLOCK_SIZE_COL,
                       (rows + BLOCK_SIZE_ROW * K - 1) / (BLOCK_SIZE_ROW * K));

  dim3 dimGrid_table_last(
      (tables.cols_last + BLOCK_SIZE_COL - 1) / BLOCK_SIZE_COL,
      (rows + BLOCK_SIZE_ROW * K - 1) / (BLOCK_SIZE_ROW * K));

  // setup configuration for mul kernel
  dim3 dimBlock_m4ri(BLOCK_SIZE_COL, BLOCK_SIZE_ROW);

  dim3 dimGrid_m4ri_n((tables.cols_n + BLOCK_SIZE_COL - 1) / BLOCK_SIZE_COL,
                      ((rows + BLOCK_SIZE_ROW - 1) / BLOCK_SIZE_ROW));

  dim3 dimGrid_m4ri_last((tables.cols_last + BLOCK_SIZE_COL - 1) /
                             BLOCK_SIZE_COL,
                         ((rows + BLOCK_SIZE_ROW - 1) / BLOCK_SIZE_ROW));

  for (int i = 0; i < tables.num_launches; i++) {
    make_table_kernel_semiring<<<dimGrid_table_n, dimBlock_table_kernel>>>(
        b, tables.table_n, tables.cols_n, rows, tables.num_tables, cols,
        i * tables.cols_n);
    cudaDeviceSynchronize();
    m4ri_mul_kernel_semiring<<<dimGrid_m4ri_n, dimBlock_m4ri>>>(
        a, c, tables.table_n, rows, cols, tables.cols_n, i * tables.cols_n);
    cudaDeviceSynchronize();
  }

  if (tables.cols_last != 0) {
    make_table_kernel_semiring<<<dimGrid_table_last, dimBlock_table_kernel>>>(
        b, tables.table_last, tables.cols_last, rows, tables.num_tables, cols,
        tables.num_launches * tables.cols_n);
    cudaDeviceSynchronize();
    m4ri_mul_kernel_semiring<<<dimGrid_m4ri_last, dimBlock_m4ri>>>(
        a, c, tables.table_last, rows, cols, tables.cols_last,
        tables.num_launches * tables.cols_n);
    cudaDeviceSynchronize();
  }

  cudaMemcpyFromSymbol(&is_c_changed, is_changed_matrix, sizeof(bool), 0,
                       cudaMemcpyDeviceToHost);
  return is_c_changed;
}
} // namespace gpu_m4ri
