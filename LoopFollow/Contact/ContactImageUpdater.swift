//
//  ContactImageUpdater.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-12-10.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import Foundation
import Contacts
import UIKit

class ContactImageUpdater {
    private let contactStore = CNContactStore()
    private let queue = DispatchQueue(label: "ContactImageUpdaterQueue")

    func updateContactImage(bgValue: String, extra: String, extra2: String, extra3: String, iob: String, cob: String, stale: Bool) {
        queue.async {
            guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
                LogManager.shared.log(category: .contact, message: "Access to contacts is not authorized.")
                return
            }

            let bundleDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "LoopFollow"
            
            // Update the main contact image with `bgValue` and `extra` (box3 = true)
            self.updateOrCreateContactImage(
                imageData: self.generateContactImage(bgValue: bgValue, extra: extra, stale: stale, box3: true)?.pngData(),
                contactName: "\(bundleDisplayName) - BG",
                box3: true
            )
            
            // Update the secondary contact image with `extra2` (box3 = false)
            self.updateOrCreateContactImage(
                imageData: self.generateContactImage(bgValue: extra2, extra: extra3, stale: stale, box3: false)?.pngData(),
                contactName: "\(bundleDisplayName) - 15min",
                box3: false
            )
            
            // Update the third contact image with `iob & cob` (box3 = false)
            self.updateOrCreateContactImage(
                imageData: self.generateContactImage(bgValue: iob, extra: cob, stale: stale, box3: false)?.pngData(),
                contactName: "\(bundleDisplayName) - IOB COB",
                box3: false
            )
        }
    }
    
    private func updateOrCreateContactImage(imageData: Data?, contactName: String, box3: Bool) {
        guard let imageData = imageData else {
            LogManager.shared.log(category: .contact, message: "Failed to generate contact image.")
            return
        }

        let predicate = CNContact.predicateForContacts(matchingName: contactName)
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactImageDataKey] as [CNKeyDescriptor]

        do {
            let contacts = try self.contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            if let contact = contacts.first, let mutableContact = contact.mutableCopy() as? CNMutableContact {
                mutableContact.imageData = imageData
                let saveRequest = CNSaveRequest()
                saveRequest.update(mutableContact)
                try self.contactStore.execute(saveRequest)
                LogManager.shared.log(category: .contact, message: "Contact image updated", isDebug: true)
            } else {
                let newContact = CNMutableContact()
                newContact.givenName = contactName
                newContact.imageData = imageData
                let saveRequest = CNSaveRequest()
                saveRequest.add(newContact, toContainerWithIdentifier: nil)
                try self.contactStore.execute(saveRequest)
                LogManager.shared.log(category: .contact, message: "New contact created")
            }
        } catch {
            LogManager.shared.log(category: .contact, message: "Failed to update or create contact: \(error)")
        }
    }
    
    private func generateContactImage(bgValue: String, extra: String, stale: Bool, box3: Bool) -> UIImage? {
        let size = CGSize(width: 300, height: 300)
        let padding: CGFloat = 0 // Padding for all rects
        let paddingHeight: CGFloat = size.height * 0.1 // Empty padding rect height
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Fill background black
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping
        
        // Height Distribution
        let timestampHeight = box3 ? size.height * 0.2 : 0
        let remainingHeight = size.height - timestampHeight - 2 * paddingHeight
        let bgHeight: CGFloat
        let extraHeight: CGFloat
        
        if box3 {
            if extra.isEmpty {
                bgHeight = remainingHeight * 0.7
                extraHeight = 0
            } else {
                bgHeight = remainingHeight * 0.6
                extraHeight = remainingHeight * 0.35
            }
        } else {
            if extra.isEmpty {
                bgHeight = remainingHeight * 0.9
                extraHeight = 0
            } else {
                bgHeight = remainingHeight * 0.45
                extraHeight = remainingHeight * 0.45
            }
        }
        
        // Helper to calculate maximum font size
        func fitFontSizeToRect(text: String, rect: CGRect, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
            var fontSize: CGFloat = rect.height
            var adjustedAttributes = attributes
            
            while fontSize > 1 {
                adjustedAttributes[.font] = UIFont.systemFont(ofSize: fontSize)
                let textSize = (text as NSString).size(withAttributes: adjustedAttributes)
                if textSize.width <= rect.width - padding * 2 && textSize.height <= rect.height - padding * 2 {
                    break
                }
                fontSize -= 1
            }
            return fontSize
        }
        
        // Draw empty padding rectangles
        let topPaddingRect = CGRect(x: 0, y: 0, width: size.width, height: paddingHeight)
        //let bottomPaddingRect = CGRect(x: 0, y: size.height - paddingHeight, width: size.width, height: paddingHeight)
        UIColor.black.setFill()
        context.fill(topPaddingRect)
        //context.fill(bottomPaddingRect)
        
        // Draw timestamp if box3 == true
        if box3 {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timestampString = formatter.string(from: Date())
            var timestampAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let timestampRect = CGRect(x: padding, y: paddingHeight, width: size.width - padding * 2, height: timestampHeight - padding * 2)
            let timestampFontSize = fitFontSizeToRect(text: timestampString, rect: timestampRect, attributes: timestampAttributes)
            timestampAttributes[.font] = UIFont.systemFont(ofSize: timestampFontSize)
            timestampString.draw(in: timestampRect, withAttributes: timestampAttributes)
        }
        
        // Draw bgRect
        var bgAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: stale ? UIColor.gray : UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        if stale {
            bgAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        let bgRect = CGRect(x: padding, y: timestampHeight + paddingHeight, width: size.width - padding * 2, height: bgHeight - padding * 2)
        let bgFontSize = fitFontSizeToRect(text: bgValue, rect: bgRect, attributes: bgAttributes)
        bgAttributes[.font] = UIFont.boldSystemFont(ofSize: bgFontSize)
        bgValue.draw(in: bgRect, withAttributes: bgAttributes)

        // Draw extraRect if extra is not empty
        if !extra.isEmpty {
            var extraAttributes: [NSAttributedString.Key: Any] = [
                                .foregroundColor: stale ? UIColor.gray : UIColor.white,
                                .paragraphStyle: paragraphStyle
                            ]
                            if stale {
                                extraAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                            }
            let extraRect = CGRect(x: padding, y: timestampHeight + bgHeight + paddingHeight, width: size.width - padding * 2, height: extraHeight - padding * 2)
            let extraFontSize = fitFontSizeToRect(text: extra, rect: extraRect, attributes: extraAttributes)
            extraAttributes[.font] = UIFont.systemFont(ofSize: extraFontSize)
            extra.draw(in: extraRect, withAttributes: extraAttributes)
        }
        
        // Render final image
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

/*
import Foundation
import Contacts
import UIKit

class ContactImageUpdater {
    private let contactStore = CNContactStore()
    private let queue = DispatchQueue(label: "ContactImageUpdaterQueue")
        
        func updateContactImage(bgValue: String, extra: String, extra2: String, extra3: String, iob: String, cob: String, stale: Bool) {
                 queue.async {
                     guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
                         LogManager.shared.log(category: .contact, message: "Access to contacts is not authorized.")
                         return
                     }
                     let bundleDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "LoopFollow"
                     
                     // Update the main contact image with `bgValue` and `extra`
                     self.updateOrCreateContactImage(
                         imageData: self.generateContactImage(bgValue: bgValue, extra: extra, stale: stale)?.pngData(),
                         contactName: "\(bundleDisplayName) - BG"
                     )
                     
                     // Update the secondary contact image with `extra2`
                     self.updateOrCreateContactImage(
                         imageData: self.generateContactImage(bgValue: extra2, extra: extra3, stale: stale)?.pngData(),
                         contactName: "\(bundleDisplayName) - 15min"
                     )
                     
                     // Update the third contact image with `iob & cob`
                     self.updateOrCreateContactImage(
                         imageData: self.generateContactImage(bgValue: iob, extra: cob, stale: stale)?.pngData(),
                         contactName: "\(bundleDisplayName) - IOB COB"
                     )
                 }
    }
    
    private func updateOrCreateContactImage(imageData: Data?, contactName: String) {
                 guard let imageData = imageData else {
                     LogManager.shared.log(category: .contact, message: "Failed to generate contact image.")
                     return
                 }
                 let predicate = CNContact.predicateForContacts(matchingName: contactName)
                 let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactImageDataKey] as [CNKeyDescriptor]

                 do {
                     let contacts = try self.contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                     if let contact = contacts.first, let mutableContact = contact.mutableCopy() as? CNMutableContact {
                         mutableContact.imageData = imageData
                         let saveRequest = CNSaveRequest()
                         saveRequest.update(mutableContact)
                         try self.contactStore.execute(saveRequest)
                         LogManager.shared.log(category: .contact, message: "Contact image updated")
                     } else {
                         let newContact = CNMutableContact()
                         newContact.givenName = contactName
                         newContact.imageData = imageData
                         let saveRequest = CNSaveRequest()
                         saveRequest.add(newContact, toContainerWithIdentifier: nil)
                         try self.contactStore.execute(saveRequest)
                         LogManager.shared.log(category: .contact, message: "New contact created")
                     }
                 } catch {
                     LogManager.shared.log(category: .contact, message: "Failed to update or create contact: \(error)")
                 }
             }
    
    private func generateContactImage(bgValue: String, extra: String, stale: Bool) -> UIImage? {
                 let size = CGSize(width: 300, height: 300)
                 UIGraphicsBeginImageContextWithOptions(size, false, 0)
                 guard let context = UIGraphicsGetCurrentContext() else { return nil }
                 UIColor.black.setFill()
                 context.fill(CGRect(origin: .zero, size: size))
                 let paragraphStyle = NSMutableParagraphStyle()
                 paragraphStyle.alignment = .center
                 let maxFontSize: CGFloat = extra.isEmpty ? 200 : 160
                 let fontSize = maxFontSize - CGFloat(bgValue.count * 15)
                 var bgAttributes: [NSAttributedString.Key: Any] = [
                     .font: UIFont.boldSystemFont(ofSize: fontSize),
                     .foregroundColor: stale ? UIColor.gray : UIColor.white,
                     .paragraphStyle: paragraphStyle
                 ]
                 if stale {
                     bgAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                 }
                 let extraAttributes: [NSAttributedString.Key: Any] = [
                     .font: UIFont.systemFont(ofSize: 90),
                     .foregroundColor: UIColor.white,
                     .paragraphStyle: paragraphStyle
                 ]
                 let bgRect = extra.isEmpty
                     ? CGRect(x: 0, y: 46, width: size.width, height: size.height - 80)
                     : CGRect(x: 0, y: 26, width: size.width, height: size.height / 2)
                 bgValue.draw(in: bgRect, withAttributes: bgAttributes)
             if !extra.isEmpty {
                     // Adjusted extraRect height by 15% less
                     let extraRect = CGRect(
                         x: 0,
                         y: size.height / 2 + 6,
                         width: size.width,
                         height: (size.height / 2 - 20) * 0.85
                     )
                     extra.draw(in: extraRect, withAttributes: extraAttributes)
                 }
                 let image = UIGraphicsGetImageFromCurrentImageContext()
                 UIGraphicsEndImageContext()
                 return image
             }
}*/
