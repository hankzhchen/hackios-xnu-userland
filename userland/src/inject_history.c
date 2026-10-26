/*
 * libredwood-history.dylib: code of ours inside com.apple.Safari.History, Safari's history daemon (build.sh's
 * INJECT names it; see inject.c for how it gets there).
 *
 * Without it Safari hangs on the first page it would put in its history (24 October 2026, the stacks of
 * logs/025641-run.log and logs/031055-run.log). Safari's main thread waits in -[WBSHistory
 * itemVisitedAtURLString:...] for the history queue, which -[WBSHistoryServiceStore loadWithCompletionHandler:]
 * holds while it waits for this daemon -- and this daemon never gets past its own main():
 *   _WBSHistoryServiceMain -> -[WBSCloudHistoryPushAgent init] -> -[APSConnection setDelegate:], which waits for
 *   the connection's queue, where -[APSConnection _connectIfNecessaryOnIvarQueue] waits for a reply from
 *   com.apple.apsd that never comes (launchd never starts apsd: not one line of it in the run).
 * The push connection is for iCloud history, which this phone has not got. So here it is declined: APSConnection's
 * designated initializer (every public one ends in it) answers nil in this process, the agent keeps a nil
 * connection -- messages to it do nothing -- and its own XPC listener still comes up. Private tabs, which keep no
 * history, loaded all along.
 */
#include <mach-o/dyld.h>
#include <objc/runtime.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define APS_CLASS       "APSConnection"
#define APS_INIT        "_initWithEnvironmentName:namedDelegatePort:enablePushDuringSleep:queue:"

static bool taken;

static void
say(const char *format, ...)
{
	static int console = -1;
	char line[300];
	va_list list;
	int length;

	if (console < 0) {
		console = open("/dev/console", O_WRONLY);
	}
	va_start(list, format);
	length = vsnprintf(line, sizeof(line), format, list);
	va_end(list);
	if (length > (int)sizeof(line) - 1) {
		length = (int)sizeof(line) - 1;
	}
	(void)write(console >= 0 ? console : 2, line, (size_t)length);
}

static id
declined_init(id self, SEL selector, id name, id port, bool sleep, id queue)
{
	(void)self, (void)selector, (void)name, (void)port, (void)sleep, (void)queue;
	say("redwood: history: an APSConnection asked for: declined, there is no apsd to answer\n");
	return NULL;
}

static void
image_added(__unused const struct mach_header *header, __unused intptr_t image_slide)
{
	Class cls;
	Method method;

	if (taken || (cls = objc_getClass(APS_CLASS)) == NULL) {
		return;
	}
	method = class_getInstanceMethod(cls, sel_registerName(APS_INIT));
	taken = true;
	if (method == NULL) {
		say("redwood: history: -[" APS_CLASS " " APS_INIT "] is not there: nothing done\n");
		return;
	}
	method_setImplementation(method, (IMP)declined_init);
	say("redwood: history: -[" APS_CLASS " " APS_INIT "] taken\n");
}

__attribute__((constructor))
static void
redwood_history_init(void)
{
	const char *name = getprogname();

	if (name == NULL || strcmp(name, "com.apple.Safari.History") != 0) {
		return;
	}
	say("redwood: history: ours is in\n");
	_dyld_register_func_for_add_image(image_added);         /* also called for every image already there */
}
