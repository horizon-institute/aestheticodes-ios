/*
 * Aestheticodes recognises a different marker scheme that allows the
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
#ifndef ImageProcessingComponent_h
#define ImageProcessingComponent_h

#import "ACXBufferManager.h"

@protocol ACXImageProcessingComponent <NSObject>

- (void) process:(ACXBufferManager*)bufferManager;

/**
 * @return true if this component can be use on segments of an image concurrently.
 */
- (bool) segmentSafe;

/**
 * @return true if using this component on segments of an image concurrently results in a
 * worthwhile performance increase.
 */
- (bool) segmentRecommended;

- (void) releaseResources;

@end

#endif /* ImageProcessingComponent_h */
