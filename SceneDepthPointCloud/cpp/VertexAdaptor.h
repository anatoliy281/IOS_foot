#ifndef VertexAdaptor_h
#define VertexAdaptor_h

#include "ShaderTypes.h"
#include "gsl/gsl.h"

#include <CGAL/Simple_cartesian.h>

using K = CGAL::Simple_cartesian<double>;
using Point = K::Point_3;

struct VertexAdaptor {
	
private:
	mtlpp::Buffer* buffer;
	gsl::span<ParticleUniforms> spanned;
	
	constexpr static auto f = [](const auto& data) {
					const auto& p = data.position;
  			return Point(p.x, p.y, p.z);
	};

public:
	VertexAdaptor(mtlpp::Buffer* vertexBuffer) : buffer {vertexBuffer} {
		const auto inContents = static_cast<ParticleUniforms*>( buffer->GetContents() );
		const auto inCount = buffer->GetLength() / sizeof(ParticleUniforms);
		spanned = {inContents, inCount};
	};
	
	auto begin() {
		return boost::make_transform_iterator(spanned.begin(), f);
	}

	auto end() {
		return boost::make_transform_iterator(spanned.end(), f);
	}
};

#endif /* VertexAdaptor_h */
