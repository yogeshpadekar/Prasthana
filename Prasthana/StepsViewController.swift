//
//  ViewController.swift
//  Prasthana
//
//  Created by Yogesh Padekar on 15/08/20.
//  Copyright © 2020 Padekar. All rights reserved.
//

import UIKit
import HealthKit
import QuickLook
import ARKit

class StepsViewController: UIViewController {
    // MARK:- IBOutlets
    @IBOutlet private var stepsLabel: UILabel!
    @IBOutlet private var targetLabel: UILabel!
    @IBOutlet private var downloadIndicator: UIActivityIndicatorView!
    
    // MARK:- Variables
    private lazy var healthStore = HKHealthStore()
    private var targetSteps = 0
    private var delayBetweenTwoChecks = 5.0
    private var greenZoneBoundary: Float = 1.0
    private var orangeZoneBoundary: Float = 0.3
    
    // MARK:- Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Register to app moved to foreground notification
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(getStepsCountPeriodically),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        //Get target if already set
        self.targetSteps = UserDefaults.standard.integer(forKey: Constants.kTargetSteps)
        if self.targetSteps > 0 {
            self.targetLabel.text = String(self.targetSteps)
        } else {
            self.targetLabel.text = Constants.kSetTarget
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Access Step Count
        let healthKitTypes: Set = [HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!]
        // Check for Authorization
        healthStore.requestAuthorization(toShare: healthKitTypes, read: healthKitTypes) { (permitted, error) in
            if (permitted) {
                // Authorization Successful, fetch steps data
                self.getStepsCountPeriodically()
            } else {
                print(error.debugDescription)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK:- IBActions
    /// IBAction which shows alert with textfield to set steps target
    @IBAction private func showSetTargetAlert() {
        let alert = UIAlertController(title: "", message: Constants.kTargetAlertMessage, preferredStyle: .alert)
        alert.addTextField() { targetTextField in
            targetTextField.keyboardType = .numberPad
            if self.targetSteps > 0 {
                targetTextField.text = String(self.targetSteps)
            }
        }
        alert.addAction(UIAlertAction(title: Constants.kOKTitle, style: .default) { action in
            if let targetTextField = alert.textFields?.first, let target = Int(targetTextField.text ?? ""), target > 0 {
                self.targetSteps = target
                if self.targetSteps > 0 {
                    targetTextField.text = String(self.targetSteps)
                    self.targetLabel.text = targetTextField.text
                    UserDefaults.standard.set(self.targetSteps, forKey: Constants.kTargetSteps)
                    UserDefaults.standard.synchronize()
                }
            }
        })
        self.present(alert, animated: true)
    }
    
    // MARK:- User defined
    /// Function to call fetchSteps periodically so that it can be used as a selector
    @objc private func getStepsCountPeriodically() {
        self.fetchSteps { (result) in
            let stepCount = Int(result)
            DispatchQueue.main.async {
                self.stepsLabel.text = String(stepCount)
                self.stepsLabel.textColor = self.stepsTextColor
                if self.targetSteps > 0, stepCount >= self.targetSteps {
                    self.showSuccessViewController()
                }
            }
        }
        
        //If the app is in foreground then periodically fetch steps data, keeping the interval of 5 seconds
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                self.perform(#selector(self.getStepsCountPeriodically), with: nil, afterDelay: self.delayBetweenTwoChecks)
            }
        }
    }
    
    /// Computed property returning color which will be set to stepsLabel to get an idea of how much goal is accomplished
    var stepsTextColor: UIColor {
        if let walkedSteps = Float(self.stepsLabel.text ?? ""), self.targetSteps > 0 {
            if walkedSteps / Float(self.targetSteps) >= self.greenZoneBoundary {
                return .green
            }
            if walkedSteps / Float(self.targetSteps) > self.orangeZoneBoundary {
                return .orange
            }
            return .red
        }
        return .black
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
    
    /// This function presents ARQuickLookPreview upon completing the target
    func showSuccessViewController() {
        //Download the usdz resource
        self.downloadIndicator.startAnimating()
        ResourceRequestManager.shared.requestResourceWith(tag: "SuccessModel", onSuccess: {
            //If download succeeds then show QLPreviewController
            DispatchQueue.main.async {
                //Reset target value
                self.targetSteps = 0
                self.targetLabel.text = Constants.kSetTarget
                UserDefaults.standard.set(0, forKey: Constants.kTargetSteps)
                
                //Show QLPreviewController
                let previewController = QLPreviewController()
                previewController.dataSource = self
                self.navigationController?.pushViewController(previewController, animated: false)
                previewController.title = Constants.kSuccessTitle
                self.downloadIndicator.stopAnimating()
            }
            
        }, onFailure: {(error) in
            print("Error in downloading the success model = \(error.debugDescription)")
            DispatchQueue.main.async {
            self.downloadIndicator.stopAnimating()
            }
        })
    }
}

extension StepsViewController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        guard let path = Bundle.main.path(forResource: "Success", ofType: "usdz") else {
            fatalError("Couldn't find the specified usdz file.")
        }
        let url = URL(fileURLWithPath: path)
        return url as QLPreviewItem
    }
}


