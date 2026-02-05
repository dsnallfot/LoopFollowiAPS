//
//  ViewControllerManager.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-07-27.

//

import Foundation
import UIKit

class ViewControllerManager {

    static let shared = ViewControllerManager()

    /* Tidigare implementation (konkret AlarmViewController)
    var alarmViewController: AlarmViewController?
    */
    var alarmViewController: AlarmUIRefreshing?

    private init() {
        instantiateAlarmViewController()
    }

    private func instantiateAlarmViewController() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)

        /*
        // Nuvarande implementation: använd legacy AlarmViewController (Eureka)
        if let legacy = storyboard.instantiateViewController(withIdentifier: "AlarmViewController") as? AlarmViewController {
            self.alarmViewController = legacy
        }
*/
        
        // Framtida implementation: växla till ModernAlarmViewController (skapad programmatiskt)
        // Avkommentera nedan och eventuellt kommentera bort legacy-blocket ovan
        // när du vill låta appen använda ModernAlarmViewController istället.
        let modern = ModernAlarmViewController()
        self.alarmViewController = modern
        return
        
    }
}
