// macOS test harness for GVDiscIO (not shipped).
#include "GVDiscIO.h"
#include <cstdio>
static void prog(void *, double f) { static int last = -1; int p = (int)(f * 100); if (p / 10 != last) { last = p / 10; fprintf(stderr, "%d%%\n", p); } }
int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: harness image dest\n"); return 2; }
  char err[256] = {0};
  int r = GVDiscIOExtract(argv[1], argv[2], prog, nullptr, nullptr, err, sizeof err);
  printf("result %d %s\n", r, err);
  return r;
}
