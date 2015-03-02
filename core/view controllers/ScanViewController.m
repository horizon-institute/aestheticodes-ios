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
#import "ScanViewController.h"
#import "MarkerSelection.h"
#import "MarkerCode.h"
#import "Experience.h"
#import "Marker.h"
#import "UIViewController+ECSlidingViewController.h"
#import "ECSlidingViewController.h"
#import "MarkerViewController.h"
#import "ExperienceListViewController.h"
#import "ExperienceSelectionViewController.h"
#import "OpenInChromeController.h"

@interface ScanViewController ()
@property MarkerSelection* markerSelection;
@property (nonatomic) NSString* selected;
@end

@implementation ScanViewController

-(void)viewDidLoad
{
    [super viewDidLoad];

	self.experience = [[ExperienceController alloc] init];
	[self.experience addListener:self];
	
	self.camera = [[MarkerCamera alloc] init];
	self.camera.delegate = self;

	self.menu.bounds = CGRectMake(self.menu.bounds.origin.x, self.menu.bounds.origin.y, self.menu.bounds.size.width, 0);
	
	self.markerSelection = [[MarkerSelection  alloc] init];
}

-(void)viewDidAppear:(BOOL)animated
{
 	[super viewDidAppear:animated];
	self.camera.experience = self.experience;
	[self.camera start:self.imageView];
    
    // adjust the size of the viewfinder depending on how much of the camera feed we are using:
    CGSize size = [[UIScreen mainScreen] bounds].size;
	float topAndBottomBarSize = 0;
	
	if(self.camera.fullSizeViewFinder)
	{
        topAndBottomBarSize = (size.height - size.width)/2.0;
		self.viewfinderLeftWidth.constant = 0;
		self.viewfinderRightWidth.constant = 0;
	}
	else
	{
        topAndBottomBarSize = (size.height - size.width/1.4)/2.0;
		float leftAndRightBarSize = (size.width - (size.width / 1.4))/2.0;
		self.viewfinderLeftWidth.constant= leftAndRightBarSize;
		self.viewfinderRightWidth.constant = leftAndRightBarSize;
	}
	
    // minimum sizes insure there is room for the toolbar and mode picker/text
    self.viewfinderTopHeight.constant = topAndBottomBarSize < 60 ? 60 : topAndBottomBarSize;
    self.viewfinderBottomHeight.constant = topAndBottomBarSize < 60 ? 60 : topAndBottomBarSize;
	
	//self.menu.bounds = CGRectMake(self.menu.bounds.origin.x, self.menu.bounds.origin.y, self.menu.bounds.size.width, 0);
	
	[self.view layoutSubviews];
	
	// If the device doesn't have a front camera disable the camera switch button
	//self.flipButton.enabled = [UIImagePickerController isCameraDeviceAvailable: UIImagePickerControllerCameraDeviceFront];
		
    // Ask the system to notify us when in forground: (removed in [self prepareForSegue])
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationEnteredForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

-(void)experienceChanged:(Experience *)experience
{
	[self markerChanged:self.selected];
}

/*!
 Called when the system tells us the app is in the forground
 */
- (void)applicationEnteredForeground:(NSNotification *)notification
{
    [self.camera start:self.imageView];
}

-(void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
	self.navigationController.navigationBarHidden = false;
	
	[self.camera stop];
}

-(IBAction)switchMarkerDisplay:(id)sender
{
	self.camera.displayMarker = (self.camera.displayMarker % 3) + 1;
	[self updateMenu];
}

-(IBAction)switchThresholdDisplay:(id)sender
{
	self.camera.displayThreshold = !self.camera.displayThreshold;
	[self updateMenu];
}

- (IBAction)switchCamera:(id)sender
{
	self.camera.rearCamera = !self.camera.rearCamera;
	[self updateMenu];
}

- (CGPathRef)makeCirclePath:(CGPoint)location radius:(CGFloat)radius
{

	UIBezierPath *path = [UIBezierPath bezierPath];
	[path addArcWithCenter:location
					radius:radius
				startAngle:0.0
				  endAngle:M_PI * 2.0
				 clockwise:YES];
	
	return path.CGPath;
}

-(IBAction)showMenu:(id)sender
{
	[self updateMenu];

	CGPoint origin = CGPointMake(CGRectGetMidX(self.menuButton.frame) - self.menu.frame.origin.x, CGRectGetMidY(self.menuButton.frame) - self.menu.frame.origin.y);
	CAShapeLayer *mask = [CAShapeLayer layer];
	mask.path = [self makeCirclePath:origin radius:0];
	mask.fillColor = [UIColor blackColor].CGColor;
	
	self.menu.layer.mask = mask;
	
	[CATransaction begin];
	CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
	animation.duration = 0.25f;
	animation.fillMode = kCAFillModeForwards;
	animation.removedOnCompletion = NO;
	
	CGPathRef newPath = [self makeCirclePath:origin radius:CGRectGetWidth(self.menu.bounds) + 20];
	
	animation.fromValue = (id)mask.path;
	animation.toValue = (__bridge id)newPath;
	
	[CATransaction setCompletionBlock:^{
		self.menu.layer.mask = nil;
	}];
	[mask addAnimation:animation forKey:@"path"];
	[CATransaction commit];
	
	self.menu.hidden = false;
	self.menuButton.hidden = true;
}

-(IBAction)hideMenu:(id)sender
{
	NSLog(@"Hide Menu");
	CGPoint origin = CGPointMake(CGRectGetMidX(self.menuButton.frame) - self.menu.frame.origin.x, CGRectGetMidY(self.menuButton.frame) - self.menu.frame.origin.y);
	CAShapeLayer *mask = [CAShapeLayer layer];
	mask.path = [self makeCirclePath:origin radius:CGRectGetWidth(self.menu.bounds) + 20];
	mask.fillColor = [UIColor blackColor].CGColor;
	
	self.menu.layer.mask = mask;
	
	[CATransaction begin];
	CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
	animation.duration = 0.25f;
	animation.fillMode = kCAFillModeForwards;
	animation.removedOnCompletion = NO;
	
	CGPathRef newPath = [self makeCirclePath:origin radius:0];
	
	animation.fromValue = (id)mask.path;
	animation.toValue = (__bridge id)newPath;
	
	[CATransaction setCompletionBlock:^{
		self.menu.hidden = true;
		self.menuButton.hidden = false;
		self.menu.layer.mask = nil;
	}];
	[mask addAnimation:animation forKey:@"path"];
	[CATransaction commit];
}

-(void)updateMenu
{
	if(self.camera.displayMarker == displaymarker_off)
	{
		if(self.switchMarkerDisplayButton.frame.size.width < 150)
		{
			[self.switchMarkerDisplayButton setTitle:@"Markers" forState:UIControlStateNormal];
		}
		else
		{
			[self.switchMarkerDisplayButton setTitle:@"Markers Hidden" forState:UIControlStateNormal];
		}
		[self.switchMarkerDisplayButton setImage:[UIImage imageNamed:@"ic_border_clear"] forState:UIControlStateNormal];
	}
	else if(self.camera.displayMarker == displaymarker_outline)
	{
		if(self.switchMarkerDisplayButton.frame.size.width < 150)
		{
			[self.switchMarkerDisplayButton setTitle:@"Markers" forState:UIControlStateNormal];
		}
		else
		{
			[self.switchMarkerDisplayButton setTitle:@"Markers Outlined" forState:UIControlStateNormal];
		}
		[self.switchMarkerDisplayButton setImage:[UIImage imageNamed: @"ic_border_outer"] forState:UIControlStateNormal];
	}
	else if(self.camera.displayMarker == displaymarker_on)
	{
		if(self.switchMarkerDisplayButton.frame.size.width < 150)
		{
			[self.switchMarkerDisplayButton setTitle:@"Markers" forState:UIControlStateNormal];
		}
		else
		{
			[self.switchMarkerDisplayButton setTitle:@"Markers Visible" forState:UIControlStateNormal];
		}
		[self.switchMarkerDisplayButton setImage:[UIImage imageNamed: @"ic_border_all"] forState:UIControlStateNormal];
	}
	
	if(self.camera.displayThreshold)
	{
		if(self.switchThresholdDisplayButton.frame.size.width < 150)
		{
			[self.switchThresholdDisplayButton setTitle:@"Threshold" forState:UIControlStateNormal];
		}
		else
		{
			[self.switchThresholdDisplayButton setTitle:@"Threshold Visible" forState:UIControlStateNormal];
		}
		[self.switchThresholdDisplayButton setImage:[UIImage imageNamed: @"ic_filter_b_and_w"] forState:UIControlStateNormal];
	}
	else
	{
		if(self.switchThresholdDisplayButton.frame.size.width < 150)
		{
			[self.switchThresholdDisplayButton setTitle:@"Threshold" forState:UIControlStateNormal];
		}
		else
		{
			[self.switchThresholdDisplayButton setTitle:@"Threshold Hidden" forState:UIControlStateNormal];
		}
		[self.switchThresholdDisplayButton setImage:[UIImage imageNamed: @"ic_filter_b_and_w_off"] forState:UIControlStateNormal];
	}

	if(self.camera.rearCamera)
	{
		if(self.switchCameraButton.frame.size.width < 150)
		{
			[self.switchCameraButton setTitle:@"Camera" forState:UIControlStateNormal];
		}
		else
		{
			[self.switchCameraButton setTitle:@"Rear Camera" forState:UIControlStateNormal];
		}
		[self.switchCameraButton setImage:[UIImage imageNamed: @"ic_camera_rear"] forState:UIControlStateNormal];
	}
	else
	{
		if(self.switchCameraButton.frame.size.width < 150)
		{
			[self.switchCameraButton setTitle:@"Camera" forState:UIControlStateNormal];
		}
		else
		{
			[self.switchCameraButton setTitle:@"Front Camera" forState:UIControlStateNormal];
		}
		[self.switchCameraButton setImage:[UIImage imageNamed: @"ic_camera_front"] forState:UIControlStateNormal];
	}
}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	self.camera.delegate = self;
	
	self.navigationController.navigationBarHidden = true;
	
	self.view.layer.shadowOpacity = 0.75f;
	self.view.layer.shadowRadius = 10.0f;
	self.view.layer.shadowColor = [UIColor blackColor].CGColor;
	
	[self.view addGestureRecognizer:self.slidingViewController.panGesture];
	[self.slidingViewController setAnchorRightRevealAmount:240.0f];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
	NSLog(@"Received memory warning");
    [self.camera stop];
}

-(UIStatusBarStyle) preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

-(void)setSelected:(NSString *)selected
{
	//NSLog(@"Selected setting to %@", selected);
	if(selected == nil)
	{
		if(_selected != nil)
		{
			_selected = nil;
			[self markerChanged:nil];
		}
	}
	else if(_selected == nil || ![selected isEqualToString:_selected])
	{
		_selected = selected;
		[self markerChanged:selected];
	}
}

-(void)markerChanged:(NSString *)markerCode
{
	NSLog(@"Selected set to %@", markerCode);
	if(markerCode)
	{
		Marker* marker = [self.experience.item getMarker:markerCode];
		if(marker)
		{
			[self openMarker:marker];
		}
	}
}

-(void)openMarker:(Marker*)marker
{
	if (marker)
	{
		NSLog(@"Action found: %@", marker.code);
		[self.camera stop];
		[self.markerSelection reset];
		if ([marker showDetail])
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.slidingViewController performSegueWithIdentifier:@"MarkerActionSegue" sender:marker];
			});
		}
		else
		{
			OpenInChromeController* chromeController = [OpenInChromeController sharedInstance];
			if ([chromeController isChromeInstalled])
			{
				[chromeController openInChrome:[NSURL URLWithString:marker.action]
								withCallbackURL:[NSURL URLWithString:@"uk.ac.horizon.aestheticodes://"]
								   createNewTab:true];
			}
			else
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					[self.slidingViewController performSegueWithIdentifier:@"MarkerActionSegue" sender:marker];
				});
			}
		}
	}
}

-(void)markersFound:(NSDictionary*)markers
{
	if(markers.count > 0)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.modeLabel setTextColor: [UIColor yellowColor]];
		});
	}
	else
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.modeLabel setTextColor: [UIColor whiteColor]];
		});
	}

	//NSLog(@"Markers found %lu", (unsigned long)markers.count);
	self.selected = [self.markerSelection addMarkers:markers];
}
@end