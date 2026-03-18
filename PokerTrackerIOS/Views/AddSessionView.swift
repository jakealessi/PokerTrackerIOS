//
//  AddSessionView.swift
//  PokerTrackerIOS
//

import SwiftUI

struct AddSessionView: View {
    private let prefill: AddSessionPrefill

    init(
        prefilledAttachedHands: [PokerSession.AttachedHand] = [],
        prefilledVariant: String? = nil,
        prefilledStakes: String? = nil,
        prefilledGameType: GameType? = nil,
        prefilledVenue: String? = nil
    ) {
        prefill = AddSessionPrefill(
            attachedHands: prefilledAttachedHands,
            variant: prefilledVariant,
            stakes: prefilledStakes,
            gameType: prefilledGameType,
            venue: prefilledVenue
        )
    }

    var body: some View {
        SessionEditorView(prefill: prefill)
    }
}

private struct AddSessionView_Previews: PreviewProvider {
    static var previews: some View {
        AddSessionView()
            .environmentObject(SessionStore())
            .environmentObject(SettingsStore())
    }
}
