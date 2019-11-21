// Definitions of Kiwi are not compatible - they have different vector sizes
struct Kiwi {
  int __attribute__ ((vector_size (8))) kiwi_x;
};

// Definitions of Lemon are not compatible - the vectors have different base types
struct Lemon {
  signed int __attribute__ ((vector_size (16))) lemon_x;
};
// codeql-extractor-compiler: clang-4.7.0
// codeql-extractor-compiler-options: -std=c99
