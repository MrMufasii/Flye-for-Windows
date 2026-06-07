#ifndef _FLYE_REGEX_SHIM_H
#define _FLYE_REGEX_SHIM_H
/*
 * Minimal POSIX <regex.h> stub for the native-Windows (MinGW-w64) Flye port.
 *
 * MinGW-w64 ships no POSIX C <regex.h>. The only consumers in samtools 1.9 are
 * bam_split.c ("samtools split") and bam_tview.c (curses, already excluded).
 * Flye never invokes either, so these stubs exist purely to let the code
 * compile and link; at runtime they report "no match".
 */
#include <stddef.h>

typedef struct { size_t re_nsub; } regex_t;
typedef ptrdiff_t regoff_t;
typedef struct { regoff_t rm_so; regoff_t rm_eo; } regmatch_t;

/* cflags */
#define REG_EXTENDED 1
#define REG_ICASE    2
#define REG_NEWLINE  4
#define REG_NOSUB    8
/* eflags */
#define REG_NOTBOL   1
#define REG_NOTEOL   2
/* error codes */
#define REG_NOMATCH  1

static inline int regcomp(regex_t *preg, const char *regex, int cflags) {
    (void)regex; (void)cflags;
    if (preg) preg->re_nsub = 0;
    return REG_NOMATCH;
}
static inline int regexec(const regex_t *preg, const char *string, size_t nmatch,
                          regmatch_t pmatch[], int eflags) {
    (void)preg; (void)string; (void)nmatch; (void)pmatch; (void)eflags;
    return REG_NOMATCH;
}
static inline size_t regerror(int errcode, const regex_t *preg,
                              char *errbuf, size_t errbuf_size) {
    (void)errcode; (void)preg;
    if (errbuf && errbuf_size) errbuf[0] = '\0';
    return 0;
}
static inline void regfree(regex_t *preg) { (void)preg; }

#endif /* _FLYE_REGEX_SHIM_H */
