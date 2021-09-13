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

-(void) triangulate {
	triangulate();
}

//-(void) triangulate:(id<MTLBuffer>)pointBuffer:
//					(id<MTLBuffer>)indexBuffer {
//	
//	triangulate( ns::Handle{(__bridge void*)pointBuffer},
//				 ns::Handle{(__bridge void*)indexBuffer} );
//	
//}

@end
