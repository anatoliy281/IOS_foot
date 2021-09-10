#import "CPPCaller.h"
#include "func.hpp"
#include "mtlpp.hpp"

@implementation CPPCaller

-(void) call {
	testCall();
}

-(void) show_buffer:(id<MTLBuffer>)buffer {
	showBufferCPP( ns::Handle{(__bridge void*)buffer} );
}

@end
