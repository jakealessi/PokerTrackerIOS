//
//  EditSessionView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct EditSessionView: View {
    let session: PokerSession

    var body: some View {
        SessionEditorView(session: session)
    }
}
