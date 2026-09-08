'use strict';
// Offline source-path diagnosis for CALLBACK-RTP-01. No running service changes.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');

const root = process.argv[2];
assert(process.argv.length === 3 && path.isAbsolute(root));
function source(name, pin) {
    const bytes = fs.readFileSync(path.join(root, 'src', name));
    assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), pin);
    return bytes.toString();
}
function body(text, signature) {
    const start = text.indexOf(signature);
    assert(start >= 0 && text.indexOf(signature, start + signature.length) < 0);
    const open = text.indexOf('{', start);
    let depth = 1, end = open + 1;
    // The two pinned bodies contain no braces inside strings or comments.
    while (depth && end < text.length) {
        const ch = text[end++];
        if (ch === '{') depth++;
        if (ch === '}') depth--;
    }
    assert.equal(depth, 0);
    return text.slice(start, end);
}
const timer = source('switch_time.c', 'ca714f0454f02b1bc57713a70fbb2d3d0aac2bfcf2fd868163c85e5f8b286284');
const rtp = source('switch_rtp.c', 'a0a0b95ece6342d9089660f3b242aa25cd97d6956136c10f030b30038f542f87');
const program = String.raw`
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <sys/types.h>
typedef int switch_status_t;
#define SWITCH_STATUS_SUCCESS 0
#define SWITCH_STATUS_GENERR -1
typedef struct { int fd; } interval_timer_t;
typedef struct { void *private_info; uint64_t tick; uint32_t samples, samplecount; } switch_timer_t;
static uint64_t expirations;
static ssize_t fixture_read(int fd, void *out, size_t count) {
    assert(fd == 19 && count == sizeof(expirations));
    memcpy(out, &expirations, count);
    return (ssize_t)count;
}
#define read fixture_read
${body(timer, 'static switch_status_t _timerfd_next(switch_timer_t *timer)')}
#undef read
#define RTP_BUG_SEND_LINEAR_TIMESTAMPS 1
#define RTP_BUG_NEVER_SEND_MARKER 2
#define SWITCH_RTP_FLAG_USE_TIMER 4
typedef struct { int rtp_bugs, flags; uint32_t ts, last_write_ts; int samples_per_interval; switch_timer_t write_timer; } switch_rtp_t;
#define switch_rtp_test_flag(s, f) ((s)->flags & (f))
#define switch_core_timer_next _timerfd_next
${body(rtp, 'static uint8_t get_next_write_ts(switch_rtp_t *rtp_session, uint32_t timestamp)')}
int main(void) {
    interval_timer_t it = {.fd = 19};
    switch_rtp_t s = {.flags = SWITCH_RTP_FLAG_USE_TIMER, .samples_per_interval = 160,
        .write_timer = {.private_info = &it, .samples = 160}};
    expirations = 1;
    get_next_write_ts(&s, 0); s.last_write_ts = s.ts;
    assert(s.ts == 160);
    expirations = 1;
    assert(get_next_write_ts(&s, 0) == 0);
    assert(s.ts - s.last_write_ts == 160); s.last_write_ts = s.ts;
    expirations = 2;
    assert(get_next_write_ts(&s, 0) == 1);
    assert(s.ts - s.last_write_ts == 320); s.last_write_ts = s.ts;
    expirations = 1;
    assert(get_next_write_ts(&s, 0) == 0);
    assert(s.ts - s.last_write_ts == 160);
    puts("{\"source_path_reproduced\":true,\"normal_timestamp_delta_samples\":160,\"two_expiration_delta_samples\":320,\"extra_media_clock_seconds\":0.02,\"marker_on_extra_tick\":true,\"captured_runtime_branch_proven\":false,\"strict_failed_run_reclassified\":false,\"network_calls\":0,\"service_changes\":0}");
}
`;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kz5-callback-timerfd-'));
const executable = path.join(dir, 'probe');
try {
    execFileSync('/usr/bin/cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-x', 'c', '-', '-o', executable],
        { input: program, timeout: 15000, maxBuffer: 65536 });
    process.stdout.write(execFileSync(executable, [], { timeout: 5000, maxBuffer: 4096 }));
} finally {
    if (fs.existsSync(executable)) fs.unlinkSync(executable);
    fs.rmdirSync(dir);
}
