/*
 * cwf_test: why wifid has no auto-join manager (24-26 October 2026). wifid makes one with
 * objc_alloc_init(CWFAutoJoinManager) (CoreWiFi) once the feature flag CoreWiFi/UnifiedAutoJoin is on
 * (it is), and logs "UAJM setup FAILED" when that is nil. This loads CoreWiFi, says where the class's
 * -init is in the shared cache (unslid, for ipsw dyld disass --vaddr), and makes one itself.
 */
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <mach-o/dyld.h>

extern const void *_dyld_get_shared_cache_range(size_t *length);

int
main(void)
{
	size_t length = 0;
	uintptr_t slide = (uintptr_t)_dyld_get_shared_cache_range(&length) - 0x180000000UL;
	void *h = dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_NOW);
	Class cls = objc_getClass("CWFAutoJoinManager");

	printf("cwf_test: uid %d, CoreWiFi %s, class %s, cache slide %#lx\n", getuid(), h ? "loaded" : dlerror(),
	    cls ? "found" : "MISSING", (unsigned long)slide);
	if (cls == nil) {
		return 1;
	}
	IMP init = class_getMethodImplementation(cls, @selector(init));
	printf("cwf_test: -[CWFAutoJoinManager init] at %#lx unslid\n", (unsigned long)((uintptr_t)init - slide));
	@autoreleasepool {
		id m = [[cls alloc] init];
		printf("cwf_test: [[CWFAutoJoinManager alloc] init] = %s\n", m ? [[m description] UTF8String] : "NIL");
	}
	return 0;
}
