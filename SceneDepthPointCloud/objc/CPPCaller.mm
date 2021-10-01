#import "CPPCaller.h"
#include "func.hpp"
#include "mtlpp.hpp"
#include "BufferPreprocessor.hpp"
#include <memory>

@interface CPPCaller()
@property (readonly) std::shared_ptr<BufferPreprocessor> bufferPreprocessor;
@end



@implementation CPPCaller

- (id)init {
   if( self = [super init] ) {
	   _bufferPreprocessor = std::make_shared<BufferPreprocessor>();
   }
   
   return self;
}


-(void) show_buffer:(id<MTLBuffer>)buffer {
	showBufferCPP( ns::Handle{(__bridge void*)buffer} );
}

-(void) preprocessPointChunk:(id<MTLBuffer>)points {
	_bufferPreprocessor->newPortion( ns::Handle{(__bridge void*)points} );
}

-(void) triangulate {
	_bufferPreprocessor->triangulate();
}

-(void) separate {
	_bufferPreprocessor->separate();
}

-(int) getIndexBuffer:(id<MTLBuffer>)indexBuffer
					 :(unsigned int)type {
	return _bufferPreprocessor->writeFaces( ns::Handle{(__bridge void*)indexBuffer}, type);
}

-(int) getVertexBuffer:(id<MTLBuffer>)pointBuffer {
	return _bufferPreprocessor->writeCoords( ns::Handle{(__bridge void*)pointBuffer}, true );
}

-(int) getPointCloudBuffer:(id<MTLBuffer>)pointBuffer {
	return _bufferPreprocessor->writeCoords( ns::Handle{(__bridge void*)pointBuffer}, false );
}

@end
