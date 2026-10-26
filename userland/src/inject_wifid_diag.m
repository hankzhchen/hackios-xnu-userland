/*
 * libredwood-wifid-diag.dylib (diagnostic, 26 October 2026): inside wifid, says what CoreWiFi's auto-join
 * manager is given and asks for. Its scan callout fails at once with error 1 ("AUTO-JOIN: Scan FAILED
 * (duration=0ms ...)"), which wifid's scan handler answers when no channel is left after its band filter.
 * Logged: the channels the manager is given (setSupportedChannels:), and every scan it asks wifid for --
 * the parameters, the channels and error that come back.
 */
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <objc/runtime.h>
#include <unistd.h>

static void
say(NSString *text)
{
	static int console = -1;
	NSData *data = [[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];

	if (console < 0) {
		console = open("/dev/console", O_WRONLY);
	}
	(void)write(console >= 0 ? console : 2, data.bytes, data.length);
}

static NSString *
brief(id object)
{
	NSString *text = [object description] ?: @"nil";

	return text.length > 1500 ? [[text substringToIndex:1500] stringByAppendingString:@"..."] : text;
}

static void (*original_set_channels)(id, SEL, id);
static id (*original_callout)(id, SEL, id, id *, NSError **);

static void
set_channels(id self, SEL selector, id channels)
{
	say([NSString stringWithFormat:@"redwood: wifid-diag: setSupportedChannels: %lu channels: %@",
	    (unsigned long)[channels count], brief(channels)]);
	original_set_channels(self, selector, channels);
}

static id
callout(id self, SEL selector, id parameters, id *channels, NSError **error)
{
	NSError *failure = nil;
	id result;

	say([NSString stringWithFormat:@"redwood: wifid-diag: scan asked for: %@", brief(parameters)]);
	result = original_callout(self, selector, parameters, channels, &failure);
	if (error != NULL) {
		*error = failure;
	}
	say([NSString stringWithFormat:@"redwood: wifid-diag: scan answered: %lu results, channels %@, error %@",
	    (unsigned long)[result count], channels != NULL ? brief(*channels) : @"-", failure ? [NSString stringWithFormat:@"%@ %ld %@",
	    failure.domain, (long)failure.code, failure.userInfo] : @"none"]);
	return result;
}


static void (*original_set_known)(id, SEL, id);
static BOOL (*original_allow_aj)(id, SEL, long long, NSError **);
static BOOL (*original_discover)(id, SEL, id, NSError **);
static BOOL (*original_allow_known)(id, SEL, id, long long, id, BOOL *, NSError **);
static BOOL (*original_allow_candidate)(id, SEL, id, long long, BOOL *, NSError **);
static BOOL (*original_perform_join)(id, SEL, id, id, NSError **);
static BOOL (*original_associate)(id, SEL, id, NSError **);

static NSString *
err(NSError *e)
{
	return e ? [NSString stringWithFormat:@"%@ %ld %@", e.domain, (long)e.code, brief(e.userInfo)] : @"none";
}

static void
set_known(id self, SEL selector, id networks)
{
	say([NSString stringWithFormat:@"redwood: wifid-diag: setKnownNetworks: %lu: %@", (unsigned long)[networks count], brief(networks)]);
	original_set_known(self, selector, networks);
}

static BOOL
allow_aj(id self, SEL selector, long long trigger, NSError **error)
{
	NSError *e = nil;
	BOOL yes = original_allow_aj(self, selector, trigger, &e);

	if (error) *error = e;
	say([NSString stringWithFormat:@"redwood: wifid-diag: allowAutoJoin(trigger %lld) = %d, error %@", trigger, yes, err(e)]);
	return yes;
}

static BOOL
discover(id self, SEL selector, id context, NSError **error)
{
	NSError *e = nil;
	BOOL yes = original_discover(self, selector, context, &e);

	if (error) *error = e;
	say([NSString stringWithFormat:@"redwood: wifid-diag: discoverKnownNetworks = %d, error %@; context %@", yes, err(e), brief(context)]);
	return yes;
}

static BOOL
allow_known(id self, SEL selector, id network, long long trigger, id transition, BOOL *defer, NSError **error)
{
	NSError *e = nil;
	BOOL yes = original_allow_known(self, selector, network, trigger, transition, defer, &e);

	if (error) *error = e;
	say([NSString stringWithFormat:@"redwood: wifid-diag: allowKnownNetwork(%@) = %d, defer %d, error %@", brief(network), yes,
	    defer ? *defer : -1, err(e)]);
	return yes;
}

static BOOL
allow_candidate(id self, SEL selector, id candidate, long long trigger, BOOL *defer, NSError **error)
{
	NSError *e = nil;
	BOOL yes = original_allow_candidate(self, selector, candidate, trigger, defer, &e);

	if (error) *error = e;
	say([NSString stringWithFormat:@"redwood: wifid-diag: allowJoinCandidate(%@) = %d, defer %d, error %@", brief(candidate), yes,
	    defer ? *defer : -1, err(e)]);
	return yes;
}

static BOOL
perform_join(id self, SEL selector, id network, id context, NSError **error)
{
	NSError *e = nil;
	BOOL yes;

	say([NSString stringWithFormat:@"redwood: wifid-diag: performJoin(%@)", brief(network)]);
	yes = original_perform_join(self, selector, network, context, &e);
	if (error) *error = e;
	say([NSString stringWithFormat:@"redwood: wifid-diag: performJoin = %d, error %@", yes, err(e)]);
	return yes;
}

static BOOL
associate(id self, SEL selector, id parameters, NSError **error)
{
	NSError *e = nil;
	BOOL yes = original_associate(self, selector, parameters, &e);

	if (error) *error = e;
	say([NSString stringWithFormat:@"redwood: wifid-diag: associate = %d, error %@", yes, err(e)]);
	return yes;
}

static void
take(Class cls, const char *name, IMP replacement, IMP *original)
{
	Method method = class_getInstanceMethod(cls, sel_registerName(name));

	if (method == NULL) {
		say([NSString stringWithFormat:@"redwood: wifid-diag: -[CWFAutoJoinManager %s] NOT FOUND", name]);
		return;
	}
	*original = method_setImplementation(method, replacement);
	say([NSString stringWithFormat:@"redwood: wifid-diag: -[CWFAutoJoinManager %s] taken", name]);
}

static bool taken;

static void
image_added(__unused const struct mach_header *header, __unused intptr_t slide)
{
	Class cls;

	if (taken || (cls = objc_getClass("CWFAutoJoinManager")) == nil) {
		return;
	}
	taken = true;
	take(cls, "setSupportedChannels:", (IMP)set_channels, (IMP *)&original_set_channels);
	take(cls, "__calloutToScanForNetworksWithParameters:scanChannels:error:", (IMP)callout, (IMP *)&original_callout);
	take(cls, "setKnownNetworks:", (IMP)set_known, (IMP *)&original_set_known);
	take(cls, "__allowAutoJoinWithTrigger:error:", (IMP)allow_aj, (IMP *)&original_allow_aj);
	take(cls, "__discoverKnownNetworksWithContext:error:", (IMP)discover, (IMP *)&original_discover);
	take(cls, "__calloutToAllowKnownNetwork:trigger:allowForSeamlessSSIDTransition:defer:error:", (IMP)allow_known,
	    (IMP *)&original_allow_known);
	take(cls, "__allowJoinCandidate:trigger:defer:error:", (IMP)allow_candidate, (IMP *)&original_allow_candidate);
	take(cls, "__performJoinWithNetwork:context:error:", (IMP)perform_join, (IMP *)&original_perform_join);
	take(cls, "__calloutToAssociateWithParameters:error:", (IMP)associate, (IMP *)&original_associate);
}

__attribute__((constructor))
static void
init(void)
{
	if (strcmp(getprogname(), "wifid") != 0) {
		return;
	}
	say(@"redwood: wifid-diag: ours is in");
	_dyld_register_func_for_add_image(image_added);         /* also called for every image already there */
}
