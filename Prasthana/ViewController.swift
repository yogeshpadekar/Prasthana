//
//  ViewController.swift
//  Prasthana
//
//  Created by Yogesh Padekar on 15/08/20.
//  Copyright © 2020 Padekar. All rights reserved.
//

import UIKit
import HealthKit

class StepsViewController: UIViewController {
    
    @IBOutlet private var stepsLabel: UILabel!
    lazy var healthStore = HKHealthStore()
    
    // MARK:- Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Register to app moved to foreground notification
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(getStepsData),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Access Step Count
               let healthKitTypes: Set = [HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!]
               // Check for Authorization
               healthStore.requestAuthorization(toShare: healthKitTypes, read: healthKitTypes) { (permitted, error) in
                   if (permitted) {
                       // Authorization Successful, fetch steps data
                    self.getStepsData()
                   } else {
                    print(error.debugDescription)
                }
               }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK:- User defined
    
    /// Function to call fetchSteps do that it can be used as a selector
    @objc private func getStepsData() {
        self.fetchSteps { (result) in
            let stepCount = String(Int(result))
            DispatchQueue.main.async {
                self.stepsLabel.text = String(stepCount)
            }
        }
        
        //If the app is in foreground then periodically fetch steps data, keeping the interval of 5 seconds
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                self.perform(#selector(self.getStepsData), with: nil, afterDelay: 5.0)
            }
        }
    }
    
    /// Function to fetch number of steps for today
    /// - Parameter completion: Completion handler with number of steps as parameter
    private func fetchSteps(completion: @escaping (Double) -> Void) {
        if let type = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            
            //Set the steps count interval to 1 day
            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            var interval = DateComponents()
            interval.day = 1
            
            //Create a query to get steps data
            let querySteps = HKStatisticsCollectionQuery(quantityType: type,
                                                         quantitySamplePredicate: nil,
                                                         options: [.cumulativeSum],
                                                         anchorDate: startOfDay,
                                                         intervalComponents: interval)
            
            /// Nested function to process steps result
            /// - Parameter sum: Health kit quantity returned
            func processStepsResult(_ sum: HKQuantity) {
                // Get steps
                let resultCount = sum.doubleValue(for: HKUnit.count())
                
                // Return
                DispatchQueue.main.async {
                    completion(resultCount)
                }
            } //End of nested function
            
            //Execute the query to get the initial data
            querySteps.initialResultsHandler = { _, result, error in
                if let validResult = result {
                    validResult.enumerateStatistics(from: startOfDay, to: now) { statistics, _ in
                        if let sum = statistics.sumQuantity() {
                            processStepsResult(sum)
                        }
                    }
                }
            }
            
            //Get updates from query
            querySteps.statisticsUpdateHandler = {
                querySteps, statistics, statisticsCollection, error in

                // If new statistics are available
                if let sum = statistics?.sumQuantity() {
                processStepsResult(sum)
                }
            }
            
            //Execute the query
            healthStore.execute(querySteps)
        }
    }
}

