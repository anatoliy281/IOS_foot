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

-(int) triangulate:(id<MTLBuffer>)indexBuffer {
	
	return _bufferPreprocessor.triangulate( ns::Handle{(__bridge void*)indexBuffer} );
	
}

-(int) getVertexBuffer:(id<MTLBuffer>)pointBuffer {
	return _bufferPreprocessor.writeVerteces( ns::Handle{(__bridge void*)pointBuffer} );
}

@end
