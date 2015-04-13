/*
 * Aestheticodes recognises a different marker scheme that allows the
 * creation of aesthetically pleasing, even beautiful, codes.
 * Copyright (C) 2015  Aestheticodes
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
#import <Foundation/Foundation.h>
#import "MarkerCode.h"
#import "MarkerCamera.h"
#import "Experience.h"
#import <UIKit/UIKit.h>
#include <vector>
#import <opencv2/opencv.hpp>
#include "ACODESMachineSettings.h"

#define NUMBER_OF_BUFFERS_MULTI_THREAD 3
#define NUMBER_OF_BUFFERS_SINGLE_THREAD 1

#define DEGREES_RADIANS(angle) ((angle) / 180.0 * M_PI)

static int REGION_INVALID = -1;
static int REGION_EMPTY = 0;

///////////////////////////

typedef enum {
    adaptiveThresholdResizeIPhone5,
    adaptiveThresholdResizeIPhone4,
    tile,
    temporalTile,
    adaptiveThresholdBehaviour
} ThresholdBehaviour;
ThresholdBehaviour thresholdBehaviour;

///////////////////////////


@protocol CvVideoCameraDelegateMod <CvVideoCameraDelegate>
@end

@interface CvVideoCameraMod : CvVideoCamera

- (void)updateOrientation;
- (void)layoutPreviewLayer;

@end

@implementation CvVideoCameraMod

- (void)updateOrientation;
{
	self->customPreviewLayer.bounds = CGRectMake(0, 0, self.parentView.frame.size.width, self.parentView.frame.size.height);
	[self layoutPreviewLayer];
}

- (void)layoutPreviewLayer;
{
	if (self.parentView != nil)
	{
		CALayer* layer = self->customPreviewLayer;
		CGRect bounds = self->customPreviewLayer.bounds;
		int rotation_angle = 0;
		
		switch (defaultAVCaptureVideoOrientation) {
			case AVCaptureVideoOrientationLandscapeRight:
				rotation_angle = 180;
				break;
			case AVCaptureVideoOrientationPortraitUpsideDown:
				rotation_angle = 270;
				break;
			case AVCaptureVideoOrientationPortrait:
				rotation_angle = 0;
			case AVCaptureVideoOrientationLandscapeLeft:
				break;
			default:
				break;
		}
		
		layer.position = CGPointMake(self.parentView.frame.size.width/2., self.parentView.frame.size.height/2.);
		layer.affineTransform = CGAffineTransformMakeRotation( DEGREES_RADIANS(rotation_angle) );
		layer.bounds = bounds;
	}
}
@end

typedef enum {
	reading, writing, available
} BufferStatus;

@interface ImageBuffer : NSObject
@property (nonatomic) cv::Mat *image;
@property (nonatomic) NSDate *creationTime;
@property (nonatomic) volatile BufferStatus status;
@end
@implementation ImageBuffer
-(ImageBuffer*)initWithImage:(cv::Mat*)inputImage
{
	self = [super init];
	self.image = inputImage;
	self.creationTime = [[NSDate alloc] init];
	self.status = available;
	return self;
}
@end

@interface ImageBufferPool : NSObject
@property (nonatomic) NSMutableArray *buffers;
@property NSLock *bufferLock;
@end
@implementation ImageBufferPool
-(ImageBufferPool*)init
{
	self = [super init];
	self.buffers = [[NSMutableArray alloc] init];
	self.bufferLock = [[NSLock alloc] init];
	return self;
}
-(void)addBuffer:(ImageBuffer*)buffer
{
	[self.bufferLock lock];
	[self.buffers addObject:buffer];
	[self.bufferLock unlock];
}
-(void)removeAll
{
	[self.bufferLock lock];
	[self.buffers removeAllObjects];
	[self.bufferLock unlock];
}
-(ImageBuffer*)getBufferToWrite
{
	ImageBuffer *oldestAvailableBuffer = nil;
	bool first = true;
	[self.bufferLock lock];
	for (ImageBuffer *buffer in self.buffers)
	{
		if (buffer.status == available && (first || [buffer.creationTime compare:oldestAvailableBuffer.creationTime]==NSOrderedAscending))
		{
			first = false;
			oldestAvailableBuffer = buffer;
		}
	}
	if (oldestAvailableBuffer!=nil)
	{
		oldestAvailableBuffer.status = writing;
	}
	[self.bufferLock unlock];
	return oldestAvailableBuffer;
}
-(void)finishedWritingToBuffer:(ImageBuffer*)buffer
{
	if (buffer!=nil)
	{
		buffer.creationTime = [[NSDate alloc] init];
		buffer.status = available;
	}
}
-(ImageBuffer*)getBufferToRead
{
	ImageBuffer *mostRecentAvailableBuffer = nil;
	bool first = true;
	[self.bufferLock lock];
	for (ImageBuffer *buffer in self.buffers)
	{
		if (buffer.status == available && (first || [buffer.creationTime compare:mostRecentAvailableBuffer.creationTime]==NSOrderedDescending))
		{
			first = false;
			mostRecentAvailableBuffer = buffer;
		}
	}
	if (mostRecentAvailableBuffer!=nil)
	{
		mostRecentAvailableBuffer.status = reading;
	}
	[self.bufferLock unlock];
	return mostRecentAvailableBuffer;
}
-(void)finishedReadingBuffer:(ImageBuffer*)buffer
{
	if (buffer!=nil)
	{
		buffer.status = available;
	}
}
-(NSUInteger)count
{
	return [self.buffers count];
}
-(ImageBuffer*)removeAvailable
{
	ImageBuffer *result = nil;
	[self.bufferLock lock];
	for (ImageBuffer* buffer in self.buffers)
	{
		if (buffer.status == available)
		{
			result = buffer;
			break;
		}
	}
	if (result!=nil)
	{
		[self.buffers removeObject:result];
	}
	[self.bufferLock unlock];
	return result;
}
@end

@interface MarkerCamera()

// Keep a strong reference to the camera settings as it will be distroyed and recreated when a new settings file is downloaded (which we replace this reference with when [self start] is called)
@property (strong) ACODESCameraSettings* cameraSettings;

// Mutex
@property bool newFrameAvaliable;
@property dispatch_semaphore_t frameReadySemaphore;
@property NSLock *detectingLock;

@property (nonatomic) ImageBufferPool *greyscaleBuffers;
@property (nonatomic) ImageBufferPool *overlayBuffers;

@property UIImageView *imageView;

@property bool singleThread;
@property bool raisedTopBorder;

@property (nonatomic, retain) CvVideoCamera* videoCamera;
@property (nonatomic) cv::Rect markerRect;
@property int minimumContourSize;
@property bool detecting;
@property bool firstFrame;
@end

@implementation MarkerCamera : NSObject

-(id)init
{
	self = [super init];
	if (self)
	{
		self.displayThreshold = false;
		self.displayMarker = displaymarker_off;
		
		_rearCamera = true;
		self.detecting = false;
        
        // init mutex
        self.newFrameAvaliable = false;
        self.frameReadySemaphore = dispatch_semaphore_create(0);
        self.detectingLock = [[NSLock alloc] init];
		
		self.fullSizeViewFinder = true;
		
		self.greyscaleBuffers = [[ImageBufferPool alloc] init];
		self.overlayBuffers = [[ImageBufferPool alloc] init];
	}
	return self;
}

- (void) start:(UIImageView*)imageView
{
    // Create OpenCV camera object:
	self.imageView = imageView;
    if (self.videoCamera == NULL)
    {
        self.videoCamera = [[CvVideoCameraMod alloc] initWithParentView:imageView];
        self.videoCamera.delegate = self;
        
        self.videoCamera.defaultAVCaptureVideoOrientation = AVCaptureVideoOrientationPortrait;
        self.videoCamera.grayscaleMode = NO;
        self.videoCamera.rotateVideo = false;
        
        [self.videoCamera unlockFocus];
    }
    
    // Set camera settings:
    self.cameraSettings = nil;
    ACODESMachineSettings* machineSettings = [ACODESMachineSettings getMachineSettings];
    
    if(self.rearCamera)
    {
        self.videoCamera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionBack;
        self.cameraSettings = [machineSettings getRearCameraSettings];
    }
    else
    {
        self.videoCamera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionFront;
        self.cameraSettings = [machineSettings getFrontCameraSettings];
    }
    
    if (self.cameraSettings)
    {
        self.videoCamera.defaultAVCaptureSessionPreset = [self.cameraSettings getAVCaptureSessionPreset];
        self.videoCamera.defaultFPS = [self.cameraSettings getDefaultFPS];
        self.singleThread = [self.cameraSettings shouldUseSingleThread];
        self.fullSizeViewFinder = [self.cameraSettings shouldUseFullscreenViewfinder];
        self.raisedTopBorder = [self.cameraSettings shouldUseRaisedTopBarViewfinder];
    }
    else
    {
        NSLog(@"Using default (low) settings");
        self.videoCamera.defaultAVCaptureSessionPreset = AVCaptureSessionPreset640x480;
        self.videoCamera.defaultFPS = 10;
        self.singleThread = true;
        self.fullSizeViewFinder = false;
        self.raisedTopBorder = false;
    }
    
    // Set threshold settings:
    NSLog(@"Threshold Behaviour setting: %@",self.experience.item.thresholdBehaviour);
    if ([self.experience.item.thresholdBehaviour isEqualToString:@"tile"])
    {
        thresholdBehaviour = tile;
    }
    else if ([self.experience.item.thresholdBehaviour isEqualToString:@"temporalTile"])
    {
        thresholdBehaviour = temporalTile;
    }
    else if ([self.experience.item.thresholdBehaviour isEqualToString:@"resize"])
    {
        thresholdBehaviour = adaptiveThresholdResizeIPhone5;
    }
    else if ([self.experience.item.thresholdBehaviour isEqualToString:@"adaptiveThreshold"])
    {
        thresholdBehaviour = adaptiveThresholdBehaviour;
    }
    else
    {
        thresholdBehaviour = temporalTile;
    }
    
    
    [self.detectingLock lock];
	if(!self.detecting)
	{
		self.detecting = true;
		
		if (!self.singleThread)
        {
			NSThread* consumerThread = [[NSThread alloc] initWithTarget:self selector:@selector(consumerLoop) object:nil];
			[consumerThread setName:@"Frame Consumer Thread"];
			[consumerThread start];
        }
	}
	[self.detectingLock unlock];
    self.firstFrame = true;

	[self.videoCamera start];
}

-(void)consumerLoop
{
	while(self.detecting)
	{
		// Sleep until a new frame is available.
		// This does not seem to increase performance but it does fix a bug where it reads the old frame when switching back to the app after detection.
		while (!self.newFrameAvaliable && self.detecting)
		{
			dispatch_semaphore_wait(self.frameReadySemaphore, DISPATCH_TIME_FOREVER);
		}
		
		if (self.detecting)
		{
			[self consumeImage];
		}
	}
}

-(void) setRearCamera:(bool)rearCamera
{
	if(_rearCamera != rearCamera)
	{
		[self stop];
		_rearCamera = rearCamera;
		self.videoCamera = nil;
		[self start:self.imageView];
	}
}

- (void) stop
{
    [self.detectingLock lock];
	self.detecting = false;
    [self.detectingLock unlock];
	if(self.videoCamera.running)
	{
		[self.videoCamera stop];
	}
	if (!self.singleThread)
	{
		// Signal the consumer thread incase it is waiting for a frame that will never be produced
		dispatch_semaphore_signal(self.frameReadySemaphore);
	}
	
	// Delete image buffers in a thread safe way:
	while ([self.greyscaleBuffers count] > 0)
	{
		ImageBuffer *buffer = [self.greyscaleBuffers removeAvailable];
		if (buffer!=nil)
		{
			delete buffer.image;
		}
	}
	while ([self.overlayBuffers count] > 0)
	{
		ImageBuffer *buffer = [self.overlayBuffers removeAvailable];
		if (buffer!=nil)
		{
			delete buffer.image;
		}
	}
}

#pragma mark - Protocol CvVideoCameraDelegate
- (void)processImage:(cv::Mat&)screenImage
{
    // 'screenImage' is the full camera image, 'image' is the region we are going to display on screen
    // note: image data is not copied, 'image' points to 'screenImage'
    cv::Mat image = screenImage(cv::Rect(self.cameraSettings.roiLeft,self.cameraSettings.roiTop,self.cameraSettings.roiWidth,self.cameraSettings.roiHeight));
    
    if (self.firstFrame) {
        self.firstFrame=false;
		self.markerRect = [self calculateMarkerImageSegmentArea:image];
		
		// setup buffers
		[self.greyscaleBuffers removeAll];
		[self.overlayBuffers removeAll];
		for (int i=0; i<(self.singleThread?NUMBER_OF_BUFFERS_SINGLE_THREAD:NUMBER_OF_BUFFERS_MULTI_THREAD); i++)
		{
			[self.greyscaleBuffers addBuffer:[[ImageBuffer alloc] initWithImage:new cv::Mat(self.markerRect.width, self.markerRect.height, CV_8UC1)]];
			ImageBuffer *buffer = [[ImageBuffer alloc] initWithImage:new cv::Mat(self.markerRect.width, self.markerRect.height, CV_8UC4)];
			buffer.image->setTo(cv::Scalar(0, 0, 0, 0));
			[self.overlayBuffers addBuffer:buffer];
		}
    }
	
	// Select image segement to be processed for marker detection.
	cv::Mat markerAreaImage(image, self.markerRect);
	
	// Get an image buffer and copy a greyscale image into it:
	ImageBuffer *greyscaleBuffer = [self.greyscaleBuffers getBufferToWrite];
	if (greyscaleBuffer!=nil)
	{
		cvtColor(markerAreaImage, *greyscaleBuffer.image, CV_BGRA2GRAY);
		
		// Signal that a new frame is ready to the consumer thread:
		[self.greyscaleBuffers finishedWritingToBuffer:greyscaleBuffer];
		self.newFrameAvaliable = true;
		if (!self.singleThread)
		{
			dispatch_semaphore_signal(self.frameReadySemaphore);
		}
		else
		{
			[self consumeImage];
		}
	}
	
	// Draw the last output image to the screen
	if(self.displayThreshold || self.displayMarker != displaymarker_off)
	{
		ImageBuffer *overlayBuffer = [self.overlayBuffers getBufferToRead];
		if (overlayBuffer!=nil)
		{
			for (int y = 0; y < overlayBuffer.image->rows; y++)
			{
				cv::Vec4b* src_pixel = markerAreaImage.ptr<cv::Vec4b>(y);
				const cv::Vec4b* ovl_pixel = overlayBuffer.image->ptr<cv::Vec4b>(y);
				for (int x = 0; x < overlayBuffer.image->cols; x++, ++src_pixel, ++ovl_pixel)
				{
					double alpha = (*ovl_pixel).val[3] / 255.0;
					for (int c = 0; c < 3; c++)
					{
						(*src_pixel).val[c] = (uchar) ((*ovl_pixel).val[c] * alpha + (*src_pixel).val[c] * (1.0 -alpha));
					}
				}
			}
			[self.overlayBuffers finishedReadingBuffer:overlayBuffer];
		}
	}
    
    if (screenImage.size != image.size)
    {
        // if the region to be displayed on screen is not the same size as the original image buffer resize it and copy it into the image buffer. (note: removing the clone will cause problems)
        cv::resize(image.clone(), screenImage, screenImage.size());
    }
}


int framesSinceLastMarker = 0;
-(void) consumeImage
{
	self.newFrameAvaliable = false;
	ImageBuffer *greyscaleBuffer = [self.greyscaleBuffers getBufferToRead];
	if (greyscaleBuffer==nil)
	{
		return;
	}
	
	// apply threshold:
	[self thresholdImage:*greyscaleBuffer.image];
	
	ImageBuffer *overlayBuffer = [self.overlayBuffers getBufferToWrite];
	if (overlayBuffer!=nil)
	{
		// prepare overlay image:
		if (self.displayThreshold)
		{
			cvtColor(*greyscaleBuffer.image, *overlayBuffer.image, CV_GRAY2RGBA);
		}
		else if(self.displayMarker != displaymarker_off)
		{
			overlayBuffer.image->setTo(cv::Scalar(0, 0, 0, 0));
		}
	}
	
	// find contours:
	cv::vector<cv::vector<cv::Point> > contours;
	cv::vector<cv::Vec4i> hierarchy;
	cv::findContours(*greyscaleBuffer.image, contours, hierarchy, CV_RETR_TREE, CV_CHAIN_APPROX_SIMPLE);
	[self.greyscaleBuffers finishedReadingBuffer:greyscaleBuffer];
	if (contours.size() > 15000)//self.experience.item.maximumContoursPerFrame)
	{
		NSLog(@"Too many contours (%lu) - skipping frame", contours.size());
		[self.overlayBuffers finishedWritingToBuffer:overlayBuffer];
		return;
	}
	
	// This autoreleasepool prevents memory allocated in [self findMarkers] from leaking.
	@autoreleasepool{
		//detect markers
		NSDictionary* markers = [self findMarkers:hierarchy andImageContour:contours];
		
		if ([markers count] > 0) {
			framesSinceLastMarker = 0;
		} else {
			++framesSinceLastMarker;
		}
		
		// draw markers to overlay image:
		if (overlayBuffer!=nil)
		{
			if(self.displayMarker != displaymarker_off)
			{
				[self drawMarkerContours:markers forImage:*overlayBuffer.image withContours:contours andHierarchy:hierarchy];
			}
			[self.overlayBuffers finishedWritingToBuffer:overlayBuffer];
		}
		
		if(self.delegate != nil)
		{
			[self.delegate markersFound:markers];
		}
	}
}

int cumulativeFramesWithoutMarker=0;
-(void) thresholdImage:(cv::Mat) image
{
	cumulativeFramesWithoutMarker += framesSinceLastMarker > 2;
    
    switch (thresholdBehaviour) {
        case adaptiveThresholdResizeIPhone5:
        {
            cv::Mat resized = cv::Mat();
            
            resize(image, resized, cv::Size(540, 540));
            
            cv::GaussianBlur(resized, resized, cv::Size(3, 3), 0);
            
            adaptiveThreshold(resized, resized, 255, cv::ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY, 151, 5);
            
            resize(resized, image, cv::Size(image.cols, image.rows));
            break;
        }
        case adaptiveThresholdResizeIPhone4:
        {
            cv::Mat resized = cv::Mat();
            
            resize(image, resized, cv::Size(320, 320));
            
            cv::GaussianBlur(resized, resized, cv::Size(5, 5), 0);
            
            adaptiveThreshold(resized, resized, 255, cv::ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY, 91, 5);
            
            resize(resized, image, cv::Size(image.cols, image.rows));
            break;
        }
        case tile:
        case temporalTile:
        {
            cv::GaussianBlur(image, image, cv::Size(3, 3), 0);
            
            
            int numberOfTiles = 1;
            if (thresholdBehaviour==temporalTile) numberOfTiles = (cumulativeFramesWithoutMarker%9)+1;
            int tileHeight = (int) image.size().height / numberOfTiles;
            int tileWidth = (int) image.size().width / numberOfTiles;
            
            // Split image into tiles and apply threshold on each image tile separately.
            for (int tileRowCount = 0; tileRowCount < numberOfTiles; tileRowCount++)
            {
                int startRow = tileRowCount * tileHeight;
                int endRow;
                if (tileRowCount < numberOfTiles - 1)
                {
                    endRow = (tileRowCount + 1) * tileHeight;
                }
                else
                {
                    endRow = (int) image.size().height;
                }
                
                for (int tileColCount = 0; tileColCount < numberOfTiles; tileColCount++)
                {
                    int startCol = tileColCount * tileWidth;
                    int endCol;
                    if (tileColCount < numberOfTiles - 1)
                    {
                        endCol = (tileColCount + 1) * tileWidth;
                    }
                    else
                    {
                        endCol = (int) image.size().width;
                    }
                    
                    cv::Mat tileMat(image, cv::Range(startRow, endRow), cv::Range(startCol, endCol));
                    threshold(tileMat, tileMat, 127, 255, cv::THRESH_OTSU);
                    tileMat.release();
                }
            }
            break;
        }
        case adaptiveThresholdBehaviour:
        {
            cv::GaussianBlur(image, image, cv::Size(3, 3), 0);
            
            adaptiveThreshold(image, image, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, 101, 5);
            
            break;
        }
    }
}

-(void)drawMarkerContours:(NSDictionary*)markers forImage:(cv::Mat)image withContours:(cv::vector<cv::vector<cv::Point> >)contours andHierarchy:(cv::vector<cv::Vec4i>)hierarchy
{
	//color to draw contours
	cv::Scalar markerColor = cv::Scalar(0, 255, 255, 255);
	cv::Scalar regionColor = cv::Scalar(0, 128, 255, 255);
	cv::Scalar outlineColor = cv::Scalar(0, 0, 0, 255);
	
	// draw markers:
	for (NSString *markerCode in markers)
	{
		MarkerCode* marker = [markers objectForKey:markerCode];
		for (NSNumber *nodeIndex in marker.nodeIndexes)
		{
			if(self.displayMarker == displaymarker_on)
			{
				cv::Vec4i nodes = hierarchy.at((int)[nodeIndex integerValue]);
				int currentRegionIndex= nodes[CHILD_NODE_INDEX];
				// Loop through the regions, verifing the value of each:
				while (currentRegionIndex >= 0)
				{
					cv::drawContours(image, contours, currentRegionIndex, outlineColor, 3, 8, hierarchy, 0, cv::Point(0, 0));
					cv::drawContours(image, contours, currentRegionIndex, regionColor, 2, 8, hierarchy, 0, cv::Point(0, 0));
					
					// Get next region:
					nodes = hierarchy.at(currentRegionIndex);
					currentRegionIndex = nodes[NEXT_SIBLING_NODE_INDEX];
				}
			}
			
			cv::drawContours(image, contours, (int)[nodeIndex integerValue], outlineColor, 3, 8, hierarchy, 0, cv::Point(0, 0));
			cv::drawContours(image, contours, (int)[nodeIndex integerValue], markerColor, 2, 8, hierarchy, 0, cv::Point(0, 0));
		}
	}

	// draw code:
	for(NSString *markerCode in markers)
	{
		MarkerCode* marker = [markers objectForKey:markerCode];
		for (NSNumber *nodeIndex in marker.nodeIndexes)
		{
			cv::Rect markerBounds = boundingRect(contours[nodeIndex.integerValue]);
			markerBounds.x = markerBounds.x;
            markerBounds.y = markerBounds.y;

			cv::putText(image, markerCode.fileSystemRepresentation, markerBounds.tl(), cv::FONT_HERSHEY_SIMPLEX, 0.5, outlineColor, 3);
			cv::putText(image, markerCode.fileSystemRepresentation, markerBounds.tl(), cv::FONT_HERSHEY_SIMPLEX, 0.5, markerColor, 2);
		}
	}
}

//calculate region in the image which is used for marker detection.
-(cv::Rect) calculateMarkerImageSegmentArea:(cv::Mat&)image
{
	int width = image.cols;
	int height = image.rows;
	
	int size = MIN(width, height);
    if (!self.fullSizeViewFinder)
    {
        size /= 1.4;
    }
	
	int x = (width - size) / 2;
	int y = (height - size) / 2;
	
	return cv::Rect(x, y, size, size);
}

#pragma mark - Parse marker code

const int CHILD_NODE_INDEX = 2;
const int NEXT_SIBLING_NODE_INDEX = 0;

-(NSDictionary*)findMarkers:(cv::vector<cv::Vec4i>)hierarchy andImageContour:(cv::vector<cv::vector<cv::Point> >)contours
{
    /*! Detected markers */
	NSMutableDictionary* markers = [[NSMutableDictionary alloc] init];
    int skippedContours = 0;
    
	for (int i = 0; i < contours.size(); i++)
	{
        if (contours[i].size() < self.cameraSettings.minimumContourSize)
        {
            ++skippedContours;
            continue;
        }
		
		NSArray* markerCode = [self createMarkerForNode:i imageHierarchy:hierarchy];
		NSString* markerKey = [MarkerCode getCodeKey:markerCode];
		if (markerKey != nil)
		{
            //NSLog(@"Found marker from contour of size %lu",contours[i].size());
			//if code is already detected.
			MarkerCode *marker = [markers objectForKey:markerKey];
			if (marker != nil)
			{
				[marker.nodeIndexes addObject:[[NSNumber alloc] initWithInt:i]];
			}
			else
			{
				marker = [[MarkerCode alloc] initWithCode:markerCode andKey:markerKey];
				[marker.nodeIndexes addObject:[[NSNumber alloc] initWithInt:i]];
				[markers setObject:marker forKey:marker.codeKey];
			}
		}
	}
    
    //NSLog(@"Skipped contours: %d/%lu",skippedContours,contours.size());
	return markers;
}


-(NSArray*)createMarkerForNode:(int)nodeIndex imageHierarchy:(cv::vector<cv::Vec4i>)imageHierarchy
{
	int currentRegionIndex = imageHierarchy.at(nodeIndex)[CHILD_NODE_INDEX];
	if (currentRegionIndex < 0)
	{
		return nil; // There are no regions.
	}
	
	int numOfRegions = 0;
	int numOfEmptyRegions = 0;
	NSMutableArray* markerCode = nil;
	NSNumber* embeddedChecksumValue = nil;
	
	// Loop through the regions, verifing the value of each:
	for (; currentRegionIndex >= 0; currentRegionIndex = imageHierarchy.at(currentRegionIndex)[NEXT_SIBLING_NODE_INDEX])
	{
		int regionValue = [self getRegionValueForRegionAtIndex:currentRegionIndex inImageHierarchy:imageHierarchy withMaxValue:self.experience.item.maxRegionValue];
		if (regionValue == REGION_EMPTY)
		{
			if(++numOfEmptyRegions > self.experience.item.maxEmptyRegions)
			{
				return nil; // Too many empty regions.
			}
		}
		
		if (regionValue == REGION_INVALID)
		{
			// Not a normal region, so look for embedded checksum:
			if (self.experience.item.checksumModulo == EMBEDDED_CHECKSUM && embeddedChecksumValue == nil) // if we've not found it yet:
			{
				embeddedChecksumValue = [self getEmbeddedChecksumValueForRegionAtIndex:currentRegionIndex inImageHierarchy:imageHierarchy];
				if (embeddedChecksumValue != nil)
				{
					continue; // this is a checksum region, so continue looking for regions
				}
			}
			
			return nil; // Too many levels.
		}
		
		if(++numOfRegions > self.experience.item.maxRegions)
		{
			return nil; // Too many regions.
		}
		
		// Add region value to code:
		if (markerCode==nil)
		{
			markerCode = [[NSMutableArray alloc] initWithObjects:@(regionValue), nil];
		}
		else
		{
			[markerCode addObject:@(regionValue)];
		}
	}
	
	// Marker should have at least one non-empty branch. If all branches are empty then return false.
	if ((numOfRegions - numOfEmptyRegions) < 1)
	{
		return nil;
	}
	
	// sort the code (the order may effect embedded checksum)
	NSArray* sortedMarkerCode = [markerCode sortedArrayUsingSelector: @selector(compare:)];
	
	if ([self.experience.item isValid:sortedMarkerCode withEmbeddedChecksum:embeddedChecksumValue reason:nil])
	{
		return sortedMarkerCode;
	}
	return nil;
}

-(int)getRegionValueForRegionAtIndex:(int)regionIndex inImageHierarchy:(cv::vector<cv::Vec4i>)imageHierarchy withMaxValue:(int)regionMaxValue
{
	// Find the first dot index:
	cv::Vec4i nodes = imageHierarchy.at(regionIndex);
	int currentDotIndex = nodes[CHILD_NODE_INDEX];
	if (currentDotIndex < 0)
	{
		return REGION_EMPTY; // There are no dots.
	}
	
	// Count all the dots and check if they are leaf nodes in the hierarchy:
	int dotCount = 0;
	while (currentDotIndex >= 0)
	{
		if ([self isValidLeaf:currentDotIndex inImageHierarchy:imageHierarchy])
		{
			dotCount++;
			// Get the next dot index:
			nodes = imageHierarchy.at(currentDotIndex);
			currentDotIndex = nodes[NEXT_SIBLING_NODE_INDEX];
			
			if (dotCount > regionMaxValue)
			{
				return REGION_INVALID; // Too many dots.
			}
		}
		else
		{
			return REGION_INVALID; // Dot is not a leaf.
		}
	}
	
	return dotCount;
}

-(bool)isValidLeaf:(int)nodeIndex inImageHierarchy:(cv::vector<cv::Vec4i>)imageHierarchy
{
	cv::Vec4i nodes = imageHierarchy.at(nodeIndex);
	return nodes[CHILD_NODE_INDEX] < 0;
}

-(NSNumber*)getEmbeddedChecksumValueForRegionAtIndex:(int)regionIndex inImageHierarchy:(cv::vector<cv::Vec4i>)imageHierarchy
{
	// Find the first dot index:
	cv::Vec4i nodes = imageHierarchy.at(regionIndex);
	int currentDotIndex = nodes[CHILD_NODE_INDEX];
	if (currentDotIndex < 0)
	{
		return nil; // There are no dots.
	}
	
	// Count all the dots and check if they are double-leaf nodes in the hierarchy:
	int dotCount = 0;
	while (currentDotIndex >= 0)
	{
		if ([self isValidDoubleLeaf:currentDotIndex inImageHierarchy:imageHierarchy])
		{
			dotCount++;
			// Get the next dot index:
			nodes = imageHierarchy.at(currentDotIndex);
			currentDotIndex = nodes[NEXT_SIBLING_NODE_INDEX];
		}
		else
		{
			return nil; // Wrong number of levels.
		}
	}
	
	return @(dotCount);
}

-(bool)isValidDoubleLeaf:(int)nodeIndex inImageHierarchy:(cv::vector<cv::Vec4i>)imageHierarchy
{
	cv::Vec4i nodes = imageHierarchy.at(nodeIndex);
	return nodes[CHILD_NODE_INDEX] >= 0 && // has a child node, and
	imageHierarchy.at(nodes[CHILD_NODE_INDEX])[NEXT_SIBLING_NODE_INDEX] < 0 && //the child has no siblings, and
	[self isValidLeaf:nodes[CHILD_NODE_INDEX] inImageHierarchy:imageHierarchy];// the child is a leaf
}

@end