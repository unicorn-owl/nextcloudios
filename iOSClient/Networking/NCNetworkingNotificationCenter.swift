//
//  NCNetworkingNotificationCenter.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 19/04/2020.
//  Copyright © 2020 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

@objc class NCNetworkingNotificationCenter: NSObject, UIDocumentInteractionControllerDelegate {
    @objc public static let shared: NCNetworkingNotificationCenter = {
        let instance = NCNetworkingNotificationCenter()
        
        NotificationCenter.default.addObserver(instance, selector: #selector(downloadedFile(_:)), name: NSNotification.Name(rawValue: k_notificationCenter_downloadedFile), object: nil)
        NotificationCenter.default.addObserver(instance, selector: #selector(uploadedFile(_:)), name: NSNotification.Name(rawValue: k_notificationCenter_uploadedFile), object: nil)
        
        return instance
    }()
    
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    var viewerQuickLook: NCViewerQuickLook?
    var docController: UIDocumentInteractionController?
    
    //MARK: - Download

    @objc func downloadedFile(_ notification: NSNotification) {
            
        if let userInfo = notification.userInfo as NSDictionary? {
            if let metadata = userInfo["metadata"] as? tableMetadata, let selector = userInfo["selector"] as? String, let errorCode = userInfo["errorCode"] as? Int, let errorDescription = userInfo["errorDescription"] as? String {
        
                if metadata.account != appDelegate.account { return }
                
                if errorCode == 0 {
                    
                    let fileURL = URL(fileURLWithPath: CCUtility.getDirectoryProviderStorageOcId(metadata.ocId, fileNameView: metadata.fileNameView))
                    
                    switch selector {
                    case selectorLoadFileQuickLook:
                        
                        let fileNamePath = NSTemporaryDirectory() + metadata.fileNameView
                        CCUtility.copyFile(atPath: CCUtility.getDirectoryProviderStorageOcId(metadata.ocId, fileNameView: metadata.fileNameView), toPath: fileNamePath)

                        viewerQuickLook = NCViewerQuickLook.init()
                        viewerQuickLook?.quickLook(url: URL(fileURLWithPath: fileNamePath))
                        
                    case selectorLoadFileView:
                        
                        if UIApplication.shared.applicationState == UIApplication.State.active {
                                                        
                            if metadata.contentType.contains("opendocument") && !NCUtility.shared.isRichDocument(metadata) {
                                
                                openIn(fileURL: fileURL, selector: selector)
                                
                            } else if metadata.typeFile == k_metadataTypeFile_compress || metadata.typeFile == k_metadataTypeFile_unknown {

                                openIn(fileURL: fileURL, selector: selector)
                                
                            } else if metadata.typeFile == k_metadataTypeFile_imagemeter {
                                
                                openIn(fileURL: fileURL, selector: selector)
                                
                            } else {
                                
                                segueMetadata(metadata)
                            }
                        }
                        
                    case selectorOpenIn, selectorOpenInDetail:
                        
                        if UIApplication.shared.applicationState == UIApplication.State.active {
                            
                            openIn(fileURL: fileURL, selector: selector)
                        }
                        
                    case selectorLoadCopy:
                        
                        var items = UIPasteboard.general.items
                        
                        do {
                            let etagPasteboard = try NSKeyedArchiver.archivedData(withRootObject: metadata.ocId, requiringSecureCoding: false)
                            items.append([k_metadataKeyedUnarchiver:etagPasteboard])
                        } catch {
                            print("error")
                        }
                        
                        UIPasteboard.general.setItems(items, options: [:])
                        
                    case selectorLoadOffline:
                        
                        NCManageDatabase.sharedInstance.setLocalFile(ocId: metadata.ocId, offline: true)
                        
                    case selectorSaveAlbum:
                        
                        let fileNamePath = CCUtility.getDirectoryProviderStorageOcId(metadata.ocId, fileNameView: metadata.fileNameView)!
                        let status = PHPhotoLibrary.authorizationStatus()

                        if metadata.typeFile == k_metadataTypeFile_image && status == PHAuthorizationStatus.authorized {
                            
                            if let image = UIImage.init(contentsOfFile: fileNamePath) {
                                UIImageWriteToSavedPhotosAlbum(image, self, #selector(SaveAlbum(_:didFinishSavingWithError:contextInfo:)), nil)
                            } else {
                                NCContentPresenter.shared.messageNotification("_save_selected_files_", description: "_file_not_saved_cameraroll_", delay: TimeInterval(k_dismissAfterSecond), type: NCContentPresenter.messageType.error, errorCode: Int(k_CCErrorFileNotSaved))
                            }
                            
                        } else if metadata.typeFile == k_metadataTypeFile_video && status == PHAuthorizationStatus.authorized {
                            
                            if UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(fileNamePath) {
                                UISaveVideoAtPathToSavedPhotosAlbum(fileNamePath, self, #selector(SaveAlbum(_:didFinishSavingWithError:contextInfo:)), nil)
                            } else {
                                NCContentPresenter.shared.messageNotification("_save_selected_files_", description: "_file_not_saved_cameraroll_", delay: TimeInterval(k_dismissAfterSecond), type: NCContentPresenter.messageType.error, errorCode: Int(k_CCErrorFileNotSaved))
                            }
                            
                        } else if status != PHAuthorizationStatus.authorized {
                            
                            NCContentPresenter.shared.messageNotification("_access_photo_not_enabled_", description: "_access_photo_not_enabled_msg_", delay: TimeInterval(k_dismissAfterSecond), type: NCContentPresenter.messageType.error, errorCode: Int(k_CCErrorFileNotSaved))
                        }
                       
                    default:
                        
                        break
                    }
                            
                } else {
                    
                    // File do not exists on server, remove in local
                    if (errorCode == k_CCErrorResourceNotFound || errorCode == k_CCErrorBadServerResponse) {
                        
                        do {
                            try FileManager.default.removeItem(atPath: CCUtility.getDirectoryProviderStorageOcId(metadata.ocId))
                        } catch { }
                        
                        NCManageDatabase.sharedInstance.deleteMetadata(predicate: NSPredicate(format: "ocId == %@", metadata.ocId))
                        NCManageDatabase.sharedInstance.deleteLocalFile(predicate: NSPredicate(format: "ocId == %@", metadata.ocId))
                        
                    } else {
                        
                        NCContentPresenter.shared.messageNotification("_download_file_", description: errorDescription, delay: TimeInterval(k_dismissAfterSecond), type: NCContentPresenter.messageType.error, errorCode: errorCode)
                    }
                }
            }
        }
    }
    
    func openIn(fileURL: URL, selector: String?) {
        
        docController = UIDocumentInteractionController(url: fileURL)
        docController?.delegate = self
        
        if selector == selectorOpenInDetail {
            guard let barButtonItem = appDelegate.activeDetail.navigationItem.rightBarButtonItem else { return }
            guard let buttonItemView = barButtonItem.value(forKey: "view") as? UIView else { return }
            
            docController?.presentOptionsMenu(from: buttonItemView.frame, in: buttonItemView, animated: true)
            
        } else {
            guard let splitViewController = appDelegate.window?.rootViewController as? UISplitViewController, let view = splitViewController.viewControllers.first?.view, let frame = splitViewController.viewControllers.first?.view.frame else {
                return }
    
            docController?.presentOptionsMenu(from: frame, in: view, animated: true)
        }
    }
    
    @objc func openShare(ViewController: UIViewController, metadata: tableMetadata, indexPage: Int) {
        
        let shareNavigationController = UIStoryboard(name: "NCShare", bundle: nil).instantiateInitialViewController() as! UINavigationController
        let shareViewController = shareNavigationController.topViewController as! NCSharePaging
        
        shareViewController.metadata = metadata
        shareViewController.indexPage = indexPage
        
        shareNavigationController.modalPresentationStyle = .formSheet
        ViewController.present(shareNavigationController, animated: true, completion: nil)
    }
        
    @objc func downloadOpen(metadata: tableMetadata, selector: String) {
        
        if CCUtility.fileProviderStorageExists(metadata.ocId, fileNameView: metadata.fileNameView) {
            
            NotificationCenter.default.postOnMainThread(name: k_notificationCenter_downloadedFile, userInfo: ["metadata": metadata, "selector": selector, "errorCode": 0, "errorDescription": "" ])
                                    
        } else {
            
            NCNetworking.shared.download(metadata: metadata, selector: selector) { (_) in }
        }
    }
    
    @objc func segueMetadata(_ metadata: tableMetadata) {
        if self.appDelegate.activeViewController is NCFiles {
            (self.appDelegate.activeViewController as! NCFiles).segue(metadata: metadata)
        } else if self.appDelegate.activeViewController is NCFavorite {
            (self.appDelegate.activeViewController as! NCFavorite).segue(metadata: metadata)
        } else if self.appDelegate.activeViewController is NCOffline {
            (self.appDelegate.activeViewController as! NCOffline).segue(metadata: metadata)
        } else if self.appDelegate.activeViewController is NCRecent {
            (self.appDelegate.activeViewController as! NCRecent).segue(metadata: metadata)
        } else if self.appDelegate.activeViewController is NCFileViewInFolder {
            (self.appDelegate.activeViewController as! NCFileViewInFolder).segue(metadata: metadata)
        }
    }
    
    @objc func SaveAlbum(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        
        if error != nil {
            NCContentPresenter.shared.messageNotification("_save_selected_files_", description: "_file_not_saved_cameraroll_", delay: TimeInterval(k_dismissAfterSecond), type: NCContentPresenter.messageType.error, errorCode: Int(k_CCErrorFileNotSaved))
        }
    }
    
    //MARK: - Upload

    @objc func uploadedFile(_ notification: NSNotification) {
    
        if let userInfo = notification.userInfo as NSDictionary? {
            if let metadata = userInfo["metadata"] as? tableMetadata, let errorCode = userInfo["errorCode"] as? Int, let errorDescription = userInfo["errorDescription"] as? String {
                                                
                if metadata.account == appDelegate.account {
                    if errorCode != 0 {
                        if errorCode != -999 && errorCode != 401 && errorDescription != "" {
                            NCContentPresenter.shared.messageNotification("_upload_file_", description: errorDescription, delay: TimeInterval(k_dismissAfterSecond), type: NCContentPresenter.messageType.error, errorCode: errorCode)
                        }
                    }
                }
            }
        }
    }
}

