/*
 * Artcodes recognises a different marker scheme that allows the
 * creation of aesthetically pleasing, even beautiful, codes.
 * Copyright (C) 2013-2015  The University of Nottingham
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU Affero General Public License as published
 *     by the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU Affero General Public License for more details.
 *
 *     You should have received a copy of the GNU Affero General Public License
 *     along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifdef __cplusplus
#import <opencv2/opencv.hpp>
#endif
#import "MarkerDetector.h"

@class DetectionSettings;
@class Marker;
@class MarkerRegion;
@class Action;

FOUNDATION_EXPORT int const CHILD_NODE_INDEX;
FOUNDATION_EXPORT int const NEXT_SIBLING_NODE_INDEX;

@interface MarkerDetector ()

@property (retain) DetectionSettings* settings;
@property double diagonalSize;

// Methods that should be protected for subclasses to override:
#ifdef __cplusplus
-(BOOL)isMarkerValidForAction:(Action*)action marker:(Marker*)marker withImageContours:(std::vector<std::vector<cv::Point> >&)contours andImageHierarchy:(std::vector<cv::Vec4i>&)hierarchy;
-(Marker*)createMarkerForNode:(int)nodeIndex imageHierarchy:(std::vector<cv::Vec4i>&)imageHierarchy andImageContour:(std::vector<std::vector<cv::Point> >&)contours;
-(MarkerRegion*)createRegionForNode:(int)regionIndex inImageHierarchy:(std::vector<cv::Vec4i>&)imageHierarchy;
-(bool)isValidLeaf:(int)nodeIndex inImageHierarchy:(std::vector<cv::Vec4i>&)imageHierarchy;
#endif
-(void)sortRegions:(NSMutableArray*) regions;
-(BOOL)isValidRegionList:(Marker*) marker;
-(BOOL)hasValidChecksum:(Marker*) marker;

@end
