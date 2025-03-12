import SwiftUI
import UserNotifications

struct UserTask: Identifiable, Codable {
    var id: UUID
    var name: String
    var date: Date
    var notificationDate: Date?
    var notificationText: String
    var reminderInterval: Int = 0
}

struct SelectedTask: Identifiable, Equatable {
    var id: UUID
    init(id: UUID = UUID()) {
        self.id = id
    }

    // Conform Equatable
    static func == (lhs: SelectedTask, rhs: SelectedTask) -> Bool {
        lhs.id == rhs.id
    }
}

struct ContentView: View {
    @State private var taskText: String = ""
    @State private var tasks: [UserTask] = []
    @State private var searchText: String = ""
    @State private var selectedTask: SelectedTask?
    @State private var showAbout = false // Staat voor de "About" popup

    init() {
        // Laad de opgeslagen taken uit UserDefaults bij het opstarten
        if let data = UserDefaults.standard.data(forKey: "tasks"),
           let savedTasks = try? JSONDecoder().decode([UserTask].self, from: data) {
            _tasks = State(initialValue: savedTasks)
        }

        // Vraag notificatiepermissie
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)

                VStack {
                    HStack {
                        TextField("Enter task...", text: $taskText, onCommit: addTask)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.default)
                            .padding()

                        Button(action: addTask) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "plus.circle.fill")
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(.blue)
                            }
                        }
                        .shadow(color: .gray.opacity(0.3), radius: 4, x: 2, y: 2)
                        .padding()
                    }

                    TextField("Search...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.default)
                        .padding()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredTasks) { task in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(task.name)
                                            .font(.headline)
                                        Text("Last time: \(task.date, formatter: dateFormatter)")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    // Toon de gele ster alleen als notificationDate in de toekomst ligt
                                    if task.reminderInterval != 0, let notificationDate = task.notificationDate, notificationDate > Date() {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                            .font(.system(size: 12))
                                    }
                                    Button(action: { deleteTask(task) }) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.white.opacity(0.8))
                                                .frame(width: 30, height: 30)
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .shadow(color: .gray.opacity(0.3), radius: 4, x: 2, y: 2)
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                                .contentShape(Rectangle())
                                .padding()
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.white]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .onTapGesture {
                                    selectedTask = SelectedTask(id: task.id)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                }
            }
            .navigationTitle("Last Time I Did")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showAbout = true }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
                    .presentationDetents([.medium])
            }
            .sheet(item: $selectedTask) { selected in
                if let index = tasks.firstIndex(where: { $0.id == selected.id }) {
                    EditTaskView(task: $tasks[index])
                } else {
                    Text("Task not found.")
                        .padding()
                }
            }
            // Sla de taken op wanneer de sheet wordt gesloten, zoals jij het wilt
            .onChange(of: selectedTask) {
                if selectedTask == nil { // Sheet is gesloten
                    saveTasks()
                }
            }
        }
    }

    var filteredTasks: [UserTask] {
        tasks.sorted(by: { $0.date > $1.date })
            .filter { searchText.isEmpty || $0.name.lowercased().contains(searchText.lowercased()) }
    }

    func addTask() {
        guard !taskText.isEmpty else { return }
        let newTask = UserTask(id: UUID(), name: taskText, date: Date(), notificationDate: nil, notificationText: "", reminderInterval: 0)
        tasks.insert(newTask, at: 0)
        saveTasks() // Sla de taken op
        DispatchQueue.main.async {
            self.taskText = ""
        }
    }

    func deleteTask(_ task: UserTask) {
        if task.reminderInterval != 0 {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
        }
        tasks.removeAll { $0.id == task.id }
        saveTasks() // Sla de taken op na verwijderen
    }

    func deleteTaskAt(offsets: IndexSet) {
        for index in offsets {
            let task = filteredTasks[index]
            if task.reminderInterval != 0 {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
            }
        }
        tasks.remove(atOffsets: offsets)
        saveTasks() // Sla de taken op na verwijderen
    }

    // Functie om taken op te slaan in UserDefaults
    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: "tasks")
        }
    }
}

struct EditTaskView: View {
    @Binding var task: UserTask
    @Environment(\.dismiss) var dismiss

    @State private var selectedInterval: Int
    @State private var notificationText: String
    @State private var notificationDate: Date

    private let intervals = [0, -1, 7, 28, 90] // None, Custom, 1 week, 4 weeks, 3 months

    init(task: Binding<UserTask>) {
        self._task = task
        self._selectedInterval = State(initialValue: task.wrappedValue.reminderInterval)
        self._notificationText = State(initialValue: task.wrappedValue.notificationText)
        self._notificationDate = State(initialValue: task.wrappedValue.notificationDate ?? task.wrappedValue.date)
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Gradiëntachtergrond voor het edit-scherm
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)

                Form {
                    TextField("Task name", text: $task.name)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.black)
                        .onChange(of: task.name) {
                            if selectedInterval != 0 {
                                notificationText = "Time to do \(task.name) again!"
                                scheduleOrRemoveNotification()
                            }
                        }

                    DatePicker("Date", selection: $task.date, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: task.date) {
                            if selectedInterval != 0 {
                                scheduleOrRemoveNotification()
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.black)

                    Picker("Reminder interval", selection: $selectedInterval) {
                        Text("None").tag(0)
                        Text("Custom").tag(-1)
                        Text("1 week").tag(7)
                        Text("4 weeks").tag(28)
                        Text("3 months").tag(90)
                    }
                    .onChange(of: selectedInterval) {
                        updateNotificationDetails(newValue: selectedInterval)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.black)

                    if selectedInterval != 0 {
                        DatePicker("Notification date", selection: $notificationDate, displayedComponents: [.date, .hourAndMinute])
                            .onChange(of: notificationDate) {
                                task.notificationDate = notificationDate
                                scheduleOrRemoveNotification()
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.black)

                        TextField("Notification text", text: $notificationText, axis: .vertical)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.black)
                            .lineLimit(3)

                        if let scheduledDate = task.notificationDate {
                            Text("Scheduled for: \(scheduledDate, formatter: dateFormatter)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.top, 5)
                        }
                    }
                }
                .background(Color.clear)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        task.reminderInterval = selectedInterval
                        task.notificationText = notificationText
                        task.notificationDate = selectedInterval != 0 ? notificationDate : nil
                        if selectedInterval != 0 {
                            scheduleOrRemoveNotification()
                        } else {
                            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private func updateNotificationDetails(newValue: Int) {
        task.reminderInterval = newValue
        if newValue > 0 {
            notificationDate = Calendar.current.date(byAdding: .day, value: newValue, to: task.date) ?? task.date
            task.notificationDate = notificationDate
            notificationText = "Time to do \(task.name) again!"
        } else if newValue == -1 { // Custom
            notificationDate = Date()
            task.notificationDate = notificationDate
            notificationText = "Time to do \(task.name) again!"
        } else {
            task.notificationDate = nil
            notificationText = ""
        }
        scheduleOrRemoveNotification()
    }

    private func scheduleOrRemoveNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
        
        guard let notificationDate = task.notificationDate, selectedInterval != 0 else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        
        if notificationDate < Date() {
            return
        }
        
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notificationDate)
        components.timeZone = TimeZone.current
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(task.name)"
        content.body = task.notificationText.isEmpty ? "Time to do \(task.name) again!" : task.notificationText
        content.sound = .default

        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { _ in
            // Geen error handling nodig
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                Text("About this app")
                    .font(.title2)
                    .padding()
                Text("Last Time I Did v1.0")
                    .font(.body)
                    .padding(.bottom, 5)
                Text("Built by Jeroen Jonckheer")
                    .font(.body)
                    .padding(.bottom, 5)
                Text("All rights reserved.")
                    .font(.body)
                Spacer()
            }
            .multilineTextAlignment(.center)
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
