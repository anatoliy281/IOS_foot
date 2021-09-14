#ifndef Perimeter_h
#define Perimeter_h

struct Perimeter {
	
	double bound;
	Perimeter(double bound) : bound(bound) {}

	template <typename AdvancingFront, typename Cell_handle>
	double operator() (const AdvancingFront& adv,
					   Cell_handle& c,
					   const int& index) const {
		// bound == 0 is better than bound < infinity
		// as it avoids the distance computations
		if(bound == 0){
			return adv.smallest_radius_delaunay_sphere (c, index);
		}
		// If perimeter > bound, return infinity so that facet is not used
		double d  = 0;
		d = sqrt(squared_distance(c->vertex((index+1)%4)->point(),
								  c->vertex((index+2)%4)->point()));
		if(d > bound)
			return adv.infinity();
		d += sqrt(squared_distance(c->vertex((index+2)%4)->point(),
								   c->vertex((index+3)%4)->point()));
		if(d > bound)
			return adv.infinity();
		d += sqrt(squared_distance(c->vertex((index+1)%4)->point(),
								   c->vertex((index+3)%4)->point()));
		if(d > bound)
			return adv.infinity();
		// Otherwise, return usual priority value: smallest radius of
		// delaunay sphere
		return adv.smallest_radius_delaunay_sphere (c, index);
	}
};

#endif /* Perimeter_h */
