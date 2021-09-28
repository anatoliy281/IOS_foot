//#if defined (_MSC_VER) && !defined (_WIN64)
//#pragma warning(disable:4244) // boost::number_distance::distance()
//							  // converts 64 to 32 bits integers
//#endif
//
//#include <CGAL/Simple_cartesian.h>
//#include <CGAL/Classification.h>
//#include <CGAL/bounding_box.h>
//#include <CGAL/tags.h>
//#include <CGAL/IO/read_points.h>
//#include <CGAL/IO/write_ply_points.h>
//#include <CGAL/Real_timer.h>
//
//#include <cstdlib>
//#include <fstream>
//#include <iostream>
//#include <string>
//#include <utility>
//
//using ConcurrencyTag = CGAL::Parallel_if_available_tag;
//using Kernel = CGAL::Simple_cartesian<double>;
//using Point = Kernel::Point_3;
//using IsoCuboid = Kernel::Iso_cuboid_3;
//using PointVector = std::vector<Point>;
//using Pmap = CGAL::Identity_property_map<Point>;
//using Color = CGAL::IO::Color;
//
//namespace Classification = CGAL::Classification;
//using Classifier		 = Classification::Sum_of_weighted_features_classifier;
//using PlanimetricGrid 	 = Classification::Planimetric_grid<Kernel, PointVector, Pmap>;
//using Neighborhood 		 = Classification::Point_set_neighborhood<Kernel, PointVector, Pmap>;
//using LocalEigenAnalysis = Classification::Local_eigen_analysis;
//using LabelHandle 		 = Classification::Label_handle;
//using FeatureHandle 	 = Classification::Feature_handle;
//using LabelSet 			 = Classification::Label_set;
//using FeatureSet 		 = Classification::Feature_set;
//
//namespace Feature = Classification::Feature;
//using DistanceToPlane = Feature::Distance_to_plane<PointVector, Pmap>;
//using Elevation = Feature::Elevation<Kernel, PointVector, Pmap>;
//using Dispersion = Feature::Vertical_dispersion<Kernel, PointVector, Pmap>;
//
//using namespace std;
//
//int foo_0 (int argc, char** argv)
//{
//	const char* filename = (argc > 1) ? argv[1] : "data/b9.ply";
//	cerr << "Reading input" << std::endl;
//	PointVector pts;
//	if ( !(CGAL::IO::read_points(filename, back_inserter(pts),
//							  // the PLY reader expects a binary file by default
//							  CGAL::parameters::use_binary_mode(false))) ) {
//		cerr << "Error: cannot read " << filename << endl;
//		return EXIT_FAILURE;
//	}
//
//	cerr << "Computing useful structures" << endl;
//
//	auto grid_resolution = 0.34f;
//	IsoCuboid bbox = CGAL::bounding_box(pts.begin(), pts.end());
//	PlanimetricGrid grid( pts,
//						 Pmap(),
//						 bbox,
//						 grid_resolution );
//
//	unsigned int number_of_neighbors = 6;
//	Neighborhood neighborhood(pts, Pmap());
//	LocalEigenAnalysis eigen = LocalEigenAnalysis::create_from_point_set( pts,
//																		 Pmap(),
//																		 neighborhood.k_neighbor_query(number_of_neighbors) );
//
//	cerr << "Computing features" << endl;
//	auto radius_neighbors = 1.7f;
//	auto radius_dtm = 15.0f;
//	FeatureSet features;
//	features.begin_parallel_additions(); // No effect in sequential mode
//	FeatureHandle distance_to_plane = features.add<DistanceToPlane>(pts, Pmap(), eigen);
//	FeatureHandle dispersion = features.add<Dispersion>(pts, Pmap(), grid, radius_neighbors);
//	FeatureHandle elevation = features.add<Elevation>(pts, Pmap(), grid, radius_dtm);
//	features.end_parallel_additions(); // No effect in sequential mode
//
//	LabelSet labels;
//	LabelHandle ground = labels.add("ground"); 	// Init name only
//	LabelHandle vegetation = labels.add("vegetation", Color(0, 255, 0)); // Init name and color
//	LabelHandle roof = labels.add ("roof", Color (255, 0, 0), 6); // Init name, Color and standard index (here, ASPRS building index)
//
//	cerr << "Setting weights" << endl;
//	Classifier classifier(labels, features);
//	classifier.set_weight(distance_to_plane, 6.75e-2f);
//	classifier.set_weight(dispersion, 5.45e-1f);
//	classifier.set_weight(elevation, 1.47e1f);
//
//	cerr << "Setting effects" << endl;
//	classifier.set_effect(ground, 		distance_to_plane, 	Classifier::NEUTRAL);
//	classifier.set_effect(ground, 		dispersion, 		Classifier::NEUTRAL);
//	classifier.set_effect(ground, 		elevation, 			Classifier::PENALIZING);
//	classifier.set_effect(vegetation, 	distance_to_plane,  Classifier::FAVORING);
//	classifier.set_effect(vegetation, 	dispersion, 		Classifier::FAVORING);
//	classifier.set_effect(vegetation, 	elevation, 			Classifier::NEUTRAL);
//	classifier.set_effect(roof, 		distance_to_plane,  Classifier::NEUTRAL);
//	classifier.set_effect(roof, 		dispersion, 		Classifier::NEUTRAL);
//	classifier.set_effect(roof, 		elevation, 			Classifier::FAVORING);
//
//	// Run classification
//	cerr << "Classifying" << endl;
//	vector<int> label_indices(pts.size(), -1);
//
//	// Timing...
//	CGAL::Real_timer t;
//	t.start();
//	Classification::classify<ConcurrencyTag>( pts,
//											labels,
//											classifier,
//											label_indices );
//	t.stop();
//
//	cerr << "Raw classification performed in " << t.time() << " second(s)" << endl;
//
////	t.reset();
////	t.start();
////	Classification::classify_with_local_smoothing<ConcurrencyTag>(pts,
////																  Pmap(),
////																  labels,
////																  classifier,
////																  neighborhood.sphere_neighbor_query(radius_neighbors),
////																  label_indices);
////	t.stop();
////
////	cerr << "Classification with local smoothing performed in " << t.time() << " second(s)" << endl;
//
////	t.reset();
////	t.start();
////	Classification::classify_with_graphcut<ConcurrencyTag>(pts,
////														   Pmap(),
////														   labels,
////														   classifier,
////														   neighborhood.k_neighbor_query(12),
////														   0.2f,
////														   4,
////														   label_indices);
////	t.stop();
////
////	cerr << "Classification with graphcut performed in " << t.time() << " second(s)" << endl;
//
//	// Save the output in a colored PLY format
//	vector<unsigned char> red, green, blue;
//	red.reserve(pts.size());
//	green.reserve(pts.size());
//	blue.reserve(pts.size());
//
//	for (size_t i = 0; i < pts.size(); ++ i) {
//		LabelHandle label = labels[ static_cast<size_t>(label_indices[i]) ];
//		tuple<unsigned, unsigned, unsigned> color;
//		if (label == ground)
//			color = make_tuple(245, 180, 0);
//		else if (label == vegetation)
//			color = make_tuple(0, 255, 27);
//		else if (label == roof)
//			color = make_tuple(255, 0, 170);
//
//		red.push_back(get<0>(color));
//		green.push_back(get<1>(color));
//		blue.push_back(get<2>(color));
//	}
//
//
//	ofstream f("classification.ply");
//	CGAL::IO::write_PLY_with_properties(f,
//										CGAL::make_range(boost::counting_iterator<std::size_t>(0),
//										boost::counting_iterator<std::size_t>(pts.size())),
//										CGAL::make_ply_point_writer (CGAL::make_property_map(pts)),
//										make_pair(CGAL::make_property_map(red), CGAL::PLY_property<unsigned char>("red")),
//										make_pair(CGAL::make_property_map(green), CGAL::PLY_property<unsigned char>("green")),
//										make_pair(CGAL::make_property_map(blue), CGAL::PLY_property<unsigned char>("blue")));
//	cerr << "All done" << endl;
//
//	return EXIT_SUCCESS;
//}



#if defined (_MSC_VER) && !defined (_WIN64)
#pragma warning(disable:4244) // boost::number_distance::distance()
							  // converts 64 to 32 bits integers
#endif
#include <CGAL/Simple_cartesian.h>
#include <CGAL/Surface_mesh.h>
#include <CGAL/Classification.h>
#include <CGAL/Real_timer.h>

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>


using Kernel = CGAL::Simple_cartesian<double>;
using Point = Kernel::Point_3;
using Mesh = CGAL::Surface_mesh<Point>;

namespace Classification = CGAL::Classification;
using LabelHandle 		 = Classification::Label_handle;
using FeatureHandle 	 = Classification::Feature_handle;
using LabelSet 			 = Classification::Label_set;
using FeatureSet 		 = Classification::Feature_set;
using Face_point_map = Classification::Face_descriptor_to_center_of_mass_map<Mesh>;
using Face_with_bbox_map = Classification::Face_descriptor_to_face_descriptor_with_bbox_map<Mesh>;
using Feature_generator = Classification::Mesh_feature_generator<Kernel, Mesh, Face_point_map>;

using namespace std;


int foo_1(int argc, char** argv)
{
	string filename = "data/b9_mesh.off";
	string filename_config = "data/b9_mesh_config.bin";
	if (argc > 1)
	filename = argv[1];
	if (argc > 2)
	filename_config = argv[2];
	Mesh mesh;
	if(!CGAL::IO::read_polygon_mesh(filename,
									mesh,
								  // the PLY reader expects a binary file by default
									CGAL::parameters::use_binary_mode(false))) {
		cerr << "Invalid input." << endl;
		return EXIT_FAILURE;
	}
	cerr << "Generating features" << endl;
	
	CGAL::Real_timer t;
	t.start();
	FeatureSet features;
	Face_point_map face_point_map (&mesh); // Associates each face to its center of mass
	size_t number_of_scales = 5;
	Feature_generator generator(mesh, face_point_map, number_of_scales);
	features.begin_parallel_additions();
	generator.generate_point_based_features (features); // Features that consider the mesh as a point set
	generator.generate_face_based_features (features);  // Features computed directly on mesh faces
	features.end_parallel_additions();
	t.stop();
	
	cerr << "Done in " << t.time() << " second(s)" << endl;
	
	LabelSet labels = { "ground", "vegetation", "roof" };
	vector<int> label_indices(mesh.number_of_faces(), -1);
	cerr << "Using ETHZ Random Forest Classifier" << endl;
	Classification::ETHZ::Random_forest_classifier classifier (labels, features);
	
	cerr << "Loading configuration" << endl;
	
	ifstream in_config (filename_config, ios_base::in | ios_base::binary);
	
	classifier.load_configuration (in_config);
	cerr << "Classifying with graphcut" << endl;
	
	t.reset();
	t.start();
	Classification::classify_with_graphcut<CGAL::Parallel_if_available_tag>
	(mesh.faces(), Face_with_bbox_map(&mesh), labels, classifier,
	 generator.neighborhood().n_ring_neighbor_query(2),
	 0.2f, 1, label_indices);
	t.stop();
	
	cerr << "Classification with graphcut done in " << t.time() << " second(s)" << endl;
	
	return EXIT_SUCCESS;
}
