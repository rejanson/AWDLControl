#import "ChromecastProcess.h"

#import <libproc.h>
#import <sys/sysctl.h>
#import <unistd.h>

static const size_t MaximumArgumentsSize = 2 * 1024 * 1024;
static const size_t MaximumChildren = 4096;

BOOL ChromecastArgumentsIndicateMirroring(const void *bytes, size_t length) {
    if (!bytes || length <= sizeof(int) || length > MaximumArgumentsSize) {
        return NO;
    }
    int argumentCount = 0;
    memcpy(&argumentCount, bytes, sizeof(argumentCount));
    if (argumentCount < 1 || (size_t)argumentCount > length - sizeof(int)) {
        return NO;
    }
    const char *cursor = (const char *)bytes + sizeof(int);
    const char *end = (const char *)bytes + length;
    const char *terminator = memchr(cursor, '\0', (size_t)(end - cursor));
    if (!terminator || terminator == cursor) {
        return NO;
    }
    cursor = terminator + 1;
    while (cursor < end && *cursor == '\0') {
        cursor++;
    }

    BOOL utility = NO;
    BOOL mirroring = NO;
    BOOL optionsEnded = NO;
    for (int index = 0; index < argumentCount; index++) {
        terminator = memchr(cursor, '\0', (size_t)(end - cursor));
        if (!terminator) {
            return NO;
        }
        // argv[0] is an executable name, not a command-line switch.
        if (index > 0 && !optionsEnded) {
            if (strcmp(cursor, "--") == 0) {
                optionsEnded = YES;
            } else if (strncmp(cursor, "--type=", 7) == 0) {
                if (utility || strcmp(cursor, "--type=utility") != 0) {
                    return NO;
                }
                utility = YES;
            } else if (strncmp(cursor, "--utility-sub-type=", 19) == 0) {
                if (mirroring || strcmp(cursor, "--utility-sub-type=mirroring.mojom.MirroringService") != 0) {
                    return NO;
                }
                mirroring = YES;
            }
        }
        cursor = terminator + 1;
    }
    return utility && mirroring;
}

static BOOL ReadProcessInfo(pid_t pid, struct proc_bsdinfo *info) {
    return pid > 0 && proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, info, sizeof(*info)) == sizeof(*info)
        && info->pbi_pid == (uint32_t)pid && info->pbi_uid == getuid();
}

static BOOL SameProcess(const struct proc_bsdinfo *before, const struct proc_bsdinfo *after) {
    return before->pbi_pid == after->pbi_pid && before->pbi_ppid == after->pbi_ppid
        && before->pbi_start_tvsec == after->pbi_start_tvsec
        && before->pbi_start_tvusec == after->pbi_start_tvusec;
}

static NSString *ProcessPath(pid_t pid) {
    char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int length = proc_pidpath(pid, path, sizeof(path));
    if (length <= 0 || !memchr(path, '\0', sizeof(path))) {
        return nil;
    }
    return [[[NSString alloc] initWithUTF8String:path] stringByResolvingSymlinksInPath];
}

static BOOL ProcessHasMirroringArguments(pid_t pid, size_t capacity) {
    void *arguments = malloc(capacity);
    if (!arguments) {
        return NO;
    }
    int mib[] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t length = capacity;
    BOOL result = sysctl(mib, 3, arguments, &length, NULL, 0) == 0
        && length <= capacity && ChromecastArgumentsIndicateMirroring(arguments, length);
    free(arguments);
    return result;
}

BOOL ChromecastBrowserHasMirroringChild(pid_t browserPID,
                                       NSString *browserExecutablePath,
                                       NSString *browserBundlePath) {
    struct proc_bsdinfo browserBefore = {0};
    if (!ReadProcessInfo(browserPID, &browserBefore)
        || ![ProcessPath(browserPID) isEqualToString:[browserExecutablePath stringByResolvingSymlinksInPath]]) {
        return NO;
    }
    int argumentMaximum = 0;
    size_t maximumSize = sizeof(argumentMaximum);
    int mib[] = {CTL_KERN, KERN_ARGMAX};
    if (sysctl(mib, 2, &argumentMaximum, &maximumSize, NULL, 0) != 0
        || maximumSize != sizeof(argumentMaximum) || argumentMaximum <= 0
        || (size_t)argumentMaximum > MaximumArgumentsSize) {
        return NO;
    }

    // A fixed upper bound avoids unbounded allocation and repeated enumeration
    // when a process exits/spawns during the snapshot. A full buffer fails open.
    pid_t children[MaximumChildren];
    int size = proc_listpids(PROC_PPID_ONLY, (uint32_t)browserPID, children, sizeof(children));
    if (size <= 0 || (size_t)size >= sizeof(children) || size % sizeof(pid_t) != 0) {
        return NO;
    }
    NSString *contentsPrefix = [[browserBundlePath stringByResolvingSymlinksInPath]
        stringByAppendingString:@"/Contents/"];
    for (size_t index = 0; index < (size_t)size / sizeof(pid_t); index++) {
        pid_t child = children[index];
        struct proc_bsdinfo before = {0};
        if (!ReadProcessInfo(child, &before) || before.pbi_ppid != (uint32_t)browserPID
            || ![ProcessPath(child) hasPrefix:contentsPrefix]) {
            continue;
        }
        if (!ProcessHasMirroringArguments(child, (size_t)argumentMaximum)) {
            continue;
        }
        // Revalidate identities after reading argv; disappearing/reused PIDs
        // must not hold AWDL disabled based on an earlier process snapshot.
        struct proc_bsdinfo after = {0};
        struct proc_bsdinfo browserAfter = {0};
        if (ReadProcessInfo(child, &after) && SameProcess(&before, &after)
            && ReadProcessInfo(browserPID, &browserAfter) && SameProcess(&browserBefore, &browserAfter)) {
            return YES;
        }
    }
    return NO;
}
