// Samples per-process CPU time, wakeups and energy over an interval (a minimal "top" for jailbroken iOS).
// Usage: nnp_proctop [seconds=30] [rows=25]
#include <libproc.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <unistd.h>

#define MAX_PROCS 2048

typedef struct {
    pid_t pid;
    char name[64];
    uint64_t cpu_abs;
    uint64_t intr_wkups;
    uint64_t idle_wkups;
    uint64_t energy_nj;
    uint64_t cycles;
    uint64_t footprint;
    int valid;
} Snap;

static int take(Snap *out) {
    pid_t pids[MAX_PROCS];
    int count = proc_listallpids(pids, sizeof(pids));
    if (count <= 0) return 0;
    int n = 0;
    for (int i = 0; i < count && n < MAX_PROCS; i++) {
        if (pids[i] <= 0) continue;
        struct rusage_info_current ru;
        memset(&ru, 0, sizeof(ru));
        if (proc_pid_rusage(pids[i], RUSAGE_INFO_CURRENT, (rusage_info_t *)&ru) != 0) continue;
        Snap *s = &out[n++];
        memset(s, 0, sizeof(*s));
        s->pid = pids[i];
        if (proc_name(pids[i], s->name, sizeof(s->name)) <= 0) snprintf(s->name, sizeof(s->name), "pid%d", pids[i]);
        s->cpu_abs = ru.ri_user_time + ru.ri_system_time;
        s->intr_wkups = ru.ri_interrupt_wkups;
        s->idle_wkups = ru.ri_pkg_idle_wkups;
        s->energy_nj = ru.ri_energy_nj;
        s->cycles = ru.ri_cycles;
        s->footprint = ru.ri_phys_footprint;
        s->valid = 1;
    }
    return n;
}

typedef struct {
    pid_t pid;
    char name[64];
    double cpu_ms;
    double wakeups;
    double power_mw;
    double mcycles;
    double footprint_mb;
} Row;

static int cmp(const void *a, const void *b) {
    const Row *x = a, *y = b;
    if (x->power_mw != y->power_mw) return x->power_mw < y->power_mw ? 1 : -1;
    return x->cpu_ms < y->cpu_ms ? 1 : (x->cpu_ms > y->cpu_ms ? -1 : 0);
}

int main(int argc, char **argv) {
    int seconds = argc > 1 ? atoi(argv[1]) : 30;
    int rows = argc > 2 ? atoi(argv[2]) : 25;
    if (seconds < 1) seconds = 30;
    static Snap before[MAX_PROCS], after[MAX_PROCS];
    int nb = take(before);
    if (nb == 0) { fprintf(stderr, "no processes visible (need root and entitlements)\n"); return 1; }
    sleep((unsigned)seconds);
    int na = take(after);

    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    static Row table[MAX_PROCS];
    int nr = 0;
    double total_power = 0, total_cpu = 0, total_wk = 0;
    for (int i = 0; i < na; i++) {
        const Snap *a = &after[i];
        const Snap *b = NULL;
        for (int j = 0; j < nb; j++) if (before[j].pid == a->pid && strcmp(before[j].name, a->name) == 0) { b = &before[j]; break; }
        if (!b) continue;
        Row *r = &table[nr++];
        r->pid = a->pid;
        snprintf(r->name, sizeof(r->name), "%s", a->name);
        uint64_t dcpu = a->cpu_abs - b->cpu_abs;
        r->cpu_ms = (double)dcpu * tb.numer / tb.denom / 1e6;
        r->wakeups = (double)((a->intr_wkups - b->intr_wkups) + (a->idle_wkups - b->idle_wkups));
        r->power_mw = (double)(a->energy_nj - b->energy_nj) / 1e6 / seconds;
        r->mcycles = (double)(a->cycles - b->cycles) / 1e6;
        r->footprint_mb = (double)a->footprint / (1024.0 * 1024.0);
        total_power += r->power_mw;
        total_cpu += r->cpu_ms;
        total_wk += r->wakeups;
    }
    qsort(table, (size_t)nr, sizeof(Row), cmp);
    printf("interval=%ds processes=%d totals: cpu=%.0fms wakeups=%.0f energy=%.1fmW\n", seconds, nr, total_cpu, total_wk, total_power);
    printf("%-6s %-32s %9s %8s %9s %9s %8s\n", "PID", "NAME", "CPU_ms", "WAKEUPS", "POWER_mW", "Mcycles", "MEM_MB");
    for (int i = 0; i < nr && i < rows; i++) {
        const Row *r = &table[i];
        printf("%-6d %-32.32s %9.1f %8.0f %9.3f %9.1f %8.1f\n", r->pid, r->name, r->cpu_ms, r->wakeups, r->power_mw, r->mcycles, r->footprint_mb);
    }
    return 0;
}
