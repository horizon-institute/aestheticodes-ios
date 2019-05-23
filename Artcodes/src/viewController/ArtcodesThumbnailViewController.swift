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

import Foundation
import UIKit
import ArtcodesScanner


open class ArtcodesThumbnailViewController
{
	
	fileprivate static let SEPARATOR_WIDTH_DP: Float = 24
	fileprivate static let VIEW_WIDTH_DP: Float = 50
	fileprivate static let IMAGE_WIDTH_DP: Float = 45
	fileprivate static let BOTTOM_MARGIN_DP: Float = 5
	fileprivate static let ANIMATION_DURATION_SECONDS: Double = 0.3
	
	let view: UIView
	
	init(view: UIView)
	{
		self.view = view
	}
	
	fileprivate var displayedViews: [MarkerImage:UIImageView]  = [:]
	fileprivate var missingViewsByPosition: [Int:UIImageView]  = [:]
	fileprivate var seperatorViewsByPosition: [Int:UIImageView]  = [:]
	
	fileprivate var existingMarkerImages: [MarkerImage?] = []
	fileprivate var existingAction: Action? = nil
	
	fileprivate let displayDensity: Float = 1.0
	
	open func update(_ currentOrFutureAction: Action?, incomingMarkerImages:[MarkerImage?]?)
	{
		let markerImages: [MarkerImage?] = incomingMarkerImages ?? []
		let existingMarkerImages: [MarkerImage?] = self.existingMarkerImages
		/*if (currentOrFutureAction == nil || markerImages.isEmpty)
		{
			self.existingMarkerImages.removeAll()
			self.existingAction = nil
		}*/
		
		let existingMatchType: Match = existingAction?.match ?? Match.any
		let currentMatchType: Match = currentOrFutureAction?.match ?? Match.any
		
		self.existingMarkerImages = markerImages
		self.existingAction = currentOrFutureAction
		
		//NSLog("markerImage: \(markerImages.map({$0?.code ?? "nil"}).joinWithSeparator(", "))")
		
		let n: Float = Float(markerImages.count)
		var viewSizePX: Float = ArtcodesThumbnailViewController.VIEW_WIDTH_DP * displayDensity
		var separatorWidthPX: Float = ArtcodesThumbnailViewController.SEPARATOR_WIDTH_DP * displayDensity
		var startX: Float = Float(view.bounds.size.width) / 2.0 - (n * viewSizePX / 2.0) - ((n-1) * separatorWidthPX / 2.0)
		
		// change sizes if larger than screen
		let totalWidth = n*viewSizePX+(n-1)*separatorWidthPX
		if (totalWidth > Float(view.bounds.size.width))
		{
			viewSizePX *= Float(view.bounds.size.width)/totalWidth
			separatorWidthPX *= Float(view.bounds.size.width)/totalWidth
			startX = 0
		}
		
		let finalTranslationY: Float = Float(view.bounds.size.height) - viewSizePX -  (ArtcodesThumbnailViewController.BOTTOM_MARGIN_DP * displayDensity)
		let finalTranslationYForSeparator: Float = finalTranslationY + (viewSizePX-separatorWidthPX)/2.0
		
		DispatchQueue.main.async(execute: {
			
			// find views that need to be removed
			var toRemove: [MarkerImage] = []
			var viewsToRemove: [UIView] = []
			for markerImage in self.displayedViews.keys
			{
				if (!markerImages.contains(where: {$0===markerImage}))
				{
					toRemove.append(markerImage)
				}
			}
			for markerImage in toRemove
			{
				viewsToRemove.append(self.displayedViews.removeValue(forKey: markerImage)!)
			}
			
			
			// remove seperators if different match type
			if (existingMatchType != currentMatchType)
			{
				for view in self.seperatorViewsByPosition.values
				{
					viewsToRemove.append(view)
				}
				self.seperatorViewsByPosition.removeAll();
			}
			
			// add new views in initial state
			var count: Int = 0
			for markerImage in markerImages
			{
				if (markerImage == nil && self.missingViewsByPosition[count]==nil)
				{
					// add new placeholder
					let imageView: UIImageView = UIImageView(frame:
						CGRect(
							x: CGFloat(startX + Float(count) * (viewSizePX + separatorWidthPX)),
							y: CGFloat(finalTranslationY),
							width: CGFloat(viewSizePX),
							height: CGFloat(viewSizePX)
						)
					)
					imageView.image = UIImage(data: UIImage(named: "marker_placeholder")!.pngData()!)
					imageView.alpha = 1
					self.view.addSubview(imageView)
					self.missingViewsByPosition[count] = imageView
				}
				else if (markerImage != nil && self.displayedViews[markerImage!] == nil)
				{
					// Add new image
					let imageView: UIImageView = UIImageView(frame:
						CGRect(
							x: CGFloat(markerImage!.x*Float(self.view.bounds.size.width)),
							y: CGFloat(markerImage!.y*Float(self.view.bounds.size.height)),
							width: CGFloat(markerImage!.width*Float(self.view.bounds.size.width)),
							height: CGFloat(markerImage!.height*Float(self.view.bounds.size.height))
						)
					)
					imageView.image = markerImage!.image
					imageView.alpha = 0
					self.view.addSubview(imageView)
					self.displayedViews[markerImage!] = imageView
					
					if (self.missingViewsByPosition[count] != nil)
					{
						viewsToRemove.append(self.missingViewsByPosition[count]!)
						self.missingViewsByPosition.removeValue(forKey: count)
					}
				}
				
				if (count < markerImages.count-1)
				{
					if (self.seperatorViewsByPosition[count] == nil)
					{
						let imageView: UIImageView = UIImageView(frame:
							CGRect(
								x: CGFloat(startX + Float(count+1) * viewSizePX + Float(count) * separatorWidthPX),
								y: CGFloat(finalTranslationYForSeparator),
								width: CGFloat(separatorWidthPX),
								height: CGFloat(separatorWidthPX)
							)
						)
						imageView.image = UIImage(data: UIImage(named: currentMatchType==Match.all ? "separator_group" : "separator_sequence")!.pngData()!)
						imageView.alpha = 0
						self.view.addSubview(imageView)
						self.seperatorViewsByPosition[count] = imageView
					}
				}
				
				count += 1
			}
			
			// remove placeholders where existingMarkerImages.count > markerImages.count
			while (count < existingMarkerImages.count)
			{
				if (self.missingViewsByPosition[count] != nil)
				{
					viewsToRemove.append(self.missingViewsByPosition.removeValue(forKey: count)!)
				}
				if (self.seperatorViewsByPosition[count-1] != nil)
				{
					viewsToRemove.append(self.seperatorViewsByPosition.removeValue(forKey: count-1)!)
				}
				count += 1
			}
			
			// start animating views
			UIView.beginAnimations("ani0", context: nil)
			UIView.setAnimationDuration(ArtcodesThumbnailViewController.ANIMATION_DURATION_SECONDS)
			
			count = 0
			for markerImage in markerImages
			{
				var viewToMove: UIImageView? = nil
				if (markerImage == nil)
				{
					viewToMove = self.missingViewsByPosition[count]
				}
				else if (markerImage != nil)
				{
					viewToMove = self.displayedViews[markerImage!]
				}
				
				if (viewToMove != nil)
				{
					viewToMove!.frame = CGRect(
						x: CGFloat(startX + Float(count) * (viewSizePX + separatorWidthPX)),
						y: CGFloat(finalTranslationY),
						width: CGFloat(viewSizePX),
						height: CGFloat(viewSizePX)
					)
					viewToMove!.alpha = 1
					viewToMove!.isHidden = false
				}
				
				if (count < markerImages.count-1)
				{
					if let seperatorView = self.seperatorViewsByPosition[count]
					{
						seperatorView.frame = CGRect(
							x: CGFloat(startX + Float(count+1) * viewSizePX + Float(count) * separatorWidthPX),
							y: CGFloat(finalTranslationYForSeparator),
							width: CGFloat(separatorWidthPX),
							height: CGFloat(separatorWidthPX)
						)
						seperatorView.alpha = 1
					}
				}
				
				count += 1
			}
			
			// animate removal of views
			for view in viewsToRemove
			{
				view.alpha = 0
			}
			
			UIView.commitAnimations()
			
			// remove views from the superview after animation
			DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(UInt64(ArtcodesThumbnailViewController.ANIMATION_DURATION_SECONDS*2) * NSEC_PER_SEC)) / Double(NSEC_PER_SEC), execute: {
				for viewToRemove: UIView in viewsToRemove
				{
					viewToRemove.removeFromSuperview()
				}
				});
		})
	}
	
	func animateRemoval(_ view: UIView?)
	{
		view?.alpha = 0
	}
	
}
