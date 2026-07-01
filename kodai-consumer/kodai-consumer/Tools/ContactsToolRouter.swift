import Foundation
import Contacts
import KodaiKernel

struct ContactsToolRouter: ToolRouter {
    let confirm: (AssistantToolCall) async -> ConfirmDecision

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        switch call {
        case let .contactsSearch(query):
            return await searchContacts(query: query)
        case .contactsCreate:
            let decision = await confirm(call)
            guard case .accept = decision else {
                return .failure(tool: "contacts_create", error: "cancelled_by_user")
            }
            return await createContact(call)
        default:
            return .failure(tool: call.toolName, error: "not_implemented")
        }
    }

    private func searchContacts(query: String) async -> ToolResult {
        let store = CNContactStore()
        do {
            try await store.requestAccess(for: .contacts)
        } catch {
            return .failure(tool: "contacts_search", error: "contacts_access_denied")
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]

        var contacts: [CNContact] = []

        do {
            let namePredicate = CNContact.predicateForContacts(matchingName: query)
            contacts = try store.unifiedContacts(matching: namePredicate, keysToFetch: keysToFetch)
        } catch {
            // fall through to empty
        }

        if contacts.isEmpty, query.contains("@") {
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            do {
                try store.enumerateContacts(with: request) { contact, stop in
                    let match = contact.emailAddresses.contains { ($0.value as String).localizedCaseInsensitiveContains(query) }
                    if match { contacts.append(contact) }
                    if contacts.count >= 10 { stop.pointee = true }
                }
            } catch { /* empty results */ }
        }

        if contacts.isEmpty, query.rangeOfCharacter(from: .decimalDigits) != nil {
            let digits = query.filter(\.isNumber)
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            do {
                try store.enumerateContacts(with: request) { contact, stop in
                    let match = contact.phoneNumbers.contains { ($0.value.stringValue).filter(\.isNumber).contains(digits) }
                    if match { contacts.append(contact) }
                    if contacts.count >= 10 { stop.pointee = true }
                }
            } catch { /* empty results */ }
        }

        let results = contacts.prefix(10)
        if results.isEmpty {
            return .ok(tool: "contacts_search", result: ["summary": "No contacts found for \"\(query)\".", "count": "0"])
        }

        let lines = results.map { c -> String in
            var line = "• \(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
            let phones = c.phoneNumbers.map { $0.value.stringValue }
            if !phones.isEmpty { line += " — \(phones.joined(separator: ", "))" }
            let emails = c.emailAddresses.map { $0.value as String }
            if !emails.isEmpty { line += " — \(emails.joined(separator: ", "))" }
            if !c.organizationName.isEmpty { line += " (\(c.organizationName))" }
            return line
        }
        let summary = "\(results.count) contact\(results.count == 1 ? "" : "s"):\n" + lines.joined(separator: "\n")
        return .ok(tool: "contacts_search", result: ["summary": summary, "count": "\(results.count)"])
    }

    private func createContact(_ call: AssistantToolCall) async -> ToolResult {
        guard case let .contactsCreate(firstName, lastName, phone, email, company, notes) = call else {
            return .failure(tool: "contacts_create", error: "invalid_call")
        }

        let store = CNContactStore()
        do {
            try await store.requestAccess(for: .contacts)
        } catch {
            return .failure(tool: "contacts_create", error: "contacts_access_denied")
        }

        let contact = CNMutableContact()
        contact.givenName = firstName
        if let lastName { contact.familyName = lastName }
        if let phone { contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))] }
        if let email { contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)] }
        if let company { contact.organizationName = company }
        if let notes { contact.note = notes }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        do {
            try store.execute(saveRequest)
            return .ok(tool: "contacts_create", result: ["name": "\(firstName) \(lastName ?? "")".trimmingCharacters(in: .whitespaces)])
        } catch {
            return .failure(tool: "contacts_create", error: error.localizedDescription)
        }
    }
}
