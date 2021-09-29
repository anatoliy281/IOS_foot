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

-(void) triangulate {
	_bufferPreprocessor.triangulate();
}

-(void) separate {
	_bufferPreprocessor.separate();
}

-(int) getIndexBuffer:(id<MTLBuffer>)indexBuffer {
	return _bufferPreprocessor.writeFaces( ns::Handle{(__bridge void*)indexBuffer} );
}

-(int) getVertexBuffer:(id<MTLBuffer>)pointBuffer {
	return _bufferPreprocessor.writeCoords( ns::Handle{(__bridge void*)pointBuffer}, true );
}

-(int) getPointCloudBuffer:(id<MTLBuffer>)pointBuffer {
	return _bufferPreprocessor.writeCoords( ns::Handle{(__bridge void*)pointBuffer}, false );
}

@end
