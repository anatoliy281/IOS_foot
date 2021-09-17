#import "CPPCaller.h"
#include "func.hpp"
#include "mtlpp.hpp"
#include "BufferPreprocessor.hpp"

@interface CPPCaller()
@property (readonly) BufferPreprocessor bufferPreprocessor;
@end

@implementation CPPCaller


-(void) show_buffer:(id<MTLBuffer>)buffer {
	showBufferCPP( ns::Handle{(__bridge void*)buffer} );
}

-(void) preprocessPointChunk:(id<MTLBuffer>)points {
	_bufferPreprocessor.newPortion( ns::Handle{(__bridge void*)points} );
}

-(void) triangulate:(id<MTLBuffer>)pointBuffer
				   :(id<MTLBuffer>)indexBuffer {
	
	_bufferPreprocessor.triangulate( ns::Handle{(__bridge void*)pointBuffer},
				 ns::Handle{(__bridge void*)indexBuffer} );
	
}

@end
