#ifndef FacetAdaptor_h
#define FacetAdaptor_h

#include <string>
#include <iostream>

using Facet = std::array<std::size_t,3>;


// Wraps index bufer and returns iterator like object that coud be passed
// CGAL::advancing_front_surface_reconstruction function
struct FacetAdaptor {
	mtlpp::Buffer* buffer;
	int position {0};
	int length;
	bool isPrev {false};
	FacetAdaptor(mtlpp::Buffer* indexBuffer) : buffer{indexBuffer} {
		length = buffer->GetLength() / sizeof(unsigned int);
		std::cout << "FacetAdaptor() position: " << position << std::endl;
	};
	
	FacetAdaptor& operator*() {
		return *this;
	}
	
	FacetAdaptor& operator++() {
		position += 3;
		if (position >= length) {
			auto error = std::string("out of index buffer: ") +
				std::to_string(position) +
				"(" + std::to_string(length) + ")";
			throw error;
		}
		return *this;
	};
	
	FacetAdaptor& operator++(int) {
		isPrev = true;
		return operator++();
	}
	
	FacetAdaptor& operator=(const Facet& facet) {
		auto curPos = (isPrev) ? position - 3 : position;
		isPrev = false;
		auto contents = static_cast<unsigned int*>( buffer->GetContents() );
		for (int i=0; i < facet.size(); ++i)
			contents[curPos+i] = static_cast<unsigned int>(facet[i]);
		
		return *this;
	}
};

#endif /* FacetAdaptor_h */
