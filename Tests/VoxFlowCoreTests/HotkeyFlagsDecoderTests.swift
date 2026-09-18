import Testing
@testable import VoxFlowCore

@Suite("HotkeyFlagsDecoder")
struct HotkeyFlagsDecoderTests {
    let rightOptionKeyCode: Int64 = 61
    let leftOptionKeyCode: Int64 = 58
    let shiftKeyCode: Int64 = 56
    let cmdKeyCode: Int64 = 55

    @Test("Right Option down decodes as down, shift not held")
    func rightOptionDownDecodes() {
        let flags = HotkeyFlagsDecoder.deviceRightOptionMask
        let result = HotkeyFlagsDecoder.decode(keyCode: rightOptionKeyCode, flags: flags, hotkey: .rightOption)
        #expect(result == HotkeyFlagsDecoder.Transition(isDown: true, shiftHeld: false))
    }

    @Test("Right Option up (device bit cleared) decodes as up")
    func rightOptionUpDecodes() {
        let result = HotkeyFlagsDecoder.decode(keyCode: rightOptionKeyCode, flags: 0, hotkey: .rightOption)
        #expect(result == HotkeyFlagsDecoder.Transition(isDown: false, shiftHeld: false))
    }

    @Test("Right Option down with Shift also held reports shiftHeld true")
    func rightOptionDownWithShiftDecodes() {
        let flags = HotkeyFlagsDecoder.deviceRightOptionMask | HotkeyFlagsDecoder.shiftMask
        let result = HotkeyFlagsDecoder.decode(keyCode: rightOptionKeyCode, flags: flags, hotkey: .rightOption)
        #expect(result == HotkeyFlagsDecoder.Transition(isDown: true, shiftHeld: true))
    }

    @Test("Right Option release with Shift still held reports shiftHeld true, isDown false")
    func rightOptionUpWithShiftStillHeldDecodes() {
        let result = HotkeyFlagsDecoder.decode(keyCode: rightOptionKeyCode, flags: HotkeyFlagsDecoder.shiftMask, hotkey: .rightOption)
        #expect(result == HotkeyFlagsDecoder.Transition(isDown: false, shiftHeld: true))
    }

    @Test("Left Option never matches, even carrying the Alternate-family flag bits")
    func leftOptionNeverMatches() {
        let flags = HotkeyFlagsDecoder.deviceLeftOptionMask
        let result = HotkeyFlagsDecoder.decode(keyCode: leftOptionKeyCode, flags: flags, hotkey: .rightOption)
        #expect(result == nil)
    }

    @Test("Plain Shift key does not match — the hot path for the common case")
    func shiftKeyDoesNotMatch() {
        let result = HotkeyFlagsDecoder.decode(keyCode: shiftKeyCode, flags: HotkeyFlagsDecoder.shiftMask, hotkey: .rightOption)
        #expect(result == nil)
    }

    @Test("Cmd key does not match")
    func cmdKeyDoesNotMatch() {
        let result = HotkeyFlagsDecoder.decode(keyCode: cmdKeyCode, flags: 0, hotkey: .rightOption)
        #expect(result == nil)
    }

    @Test("A stray Right-Option-bit set on an unrelated keycode still does not match — keycode gates first")
    func unrelatedKeycodeWithRightOptionBitStillDoesNotMatch() {
        // Defensive: confirms the decoder gates on keyCode, not just the
        // flags bitmask, since some non-Option keyboard events could in
        // principle carry stray high bits.
        let result = HotkeyFlagsDecoder.decode(keyCode: shiftKeyCode, flags: HotkeyFlagsDecoder.deviceRightOptionMask, hotkey: .rightOption)
        #expect(result == nil)
    }

    // MARK: - Step 11a: the other 3 selectable hotkey options, same coverage
    // shape as Right Option above, using each option's own verified
    // keyCode/deviceMask pair.

    @Test("Right Command down/up decode correctly, and Right Option's keycode/mask don't cross-match it")
    func rightCommandDecodes() {
        let down = HotkeyFlagsDecoder.decode(keyCode: HotkeyOption.rightCommand.virtualKeyCode, flags: HotkeyOption.rightCommand.deviceMask, hotkey: .rightCommand)
        #expect(down == HotkeyFlagsDecoder.Transition(isDown: true, shiftHeld: false))

        let up = HotkeyFlagsDecoder.decode(keyCode: HotkeyOption.rightCommand.virtualKeyCode, flags: 0, hotkey: .rightCommand)
        #expect(up == HotkeyFlagsDecoder.Transition(isDown: false, shiftHeld: false))

        // Right Option's own physical keycode must not match while Right
        // Command is the configured hotkey.
        let crossMatch = HotkeyFlagsDecoder.decode(keyCode: rightOptionKeyCode, flags: HotkeyFlagsDecoder.deviceRightOptionMask, hotkey: .rightCommand)
        #expect(crossMatch == nil)
    }

    @Test("Left Option down/up decode correctly, and Right Option's keycode/mask don't cross-match it")
    func leftOptionDecodes() {
        let down = HotkeyFlagsDecoder.decode(keyCode: HotkeyOption.leftOption.virtualKeyCode, flags: HotkeyOption.leftOption.deviceMask, hotkey: .leftOption)
        #expect(down == HotkeyFlagsDecoder.Transition(isDown: true, shiftHeld: false))

        let up = HotkeyFlagsDecoder.decode(keyCode: HotkeyOption.leftOption.virtualKeyCode, flags: 0, hotkey: .leftOption)
        #expect(up == HotkeyFlagsDecoder.Transition(isDown: false, shiftHeld: false))

        let crossMatch = HotkeyFlagsDecoder.decode(keyCode: rightOptionKeyCode, flags: HotkeyFlagsDecoder.deviceRightOptionMask, hotkey: .leftOption)
        #expect(crossMatch == nil)
    }

    @Test("Left Command down/up decode correctly, and Right Command's keycode/mask don't cross-match it")
    func leftCommandDecodes() {
        let down = HotkeyFlagsDecoder.decode(keyCode: HotkeyOption.leftCommand.virtualKeyCode, flags: HotkeyOption.leftCommand.deviceMask, hotkey: .leftCommand)
        #expect(down == HotkeyFlagsDecoder.Transition(isDown: true, shiftHeld: false))

        let up = HotkeyFlagsDecoder.decode(keyCode: HotkeyOption.leftCommand.virtualKeyCode, flags: 0, hotkey: .leftCommand)
        #expect(up == HotkeyFlagsDecoder.Transition(isDown: false, shiftHeld: false))

        let crossMatch = HotkeyFlagsDecoder.decode(keyCode: HotkeyOption.rightCommand.virtualKeyCode, flags: HotkeyOption.rightCommand.deviceMask, hotkey: .leftCommand)
        #expect(crossMatch == nil)
    }

    @Test("every HotkeyOption has a distinct virtualKeyCode and a distinct deviceMask")
    func everyHotkeyOptionIsDistinct() {
        let keyCodes = HotkeyOption.allCases.map { $0.virtualKeyCode }
        #expect(Set(keyCodes).count == HotkeyOption.allCases.count)
        let masks = HotkeyOption.allCases.map { $0.deviceMask }
        #expect(Set(masks).count == HotkeyOption.allCases.count)
    }

    @Test("switching the configured hotkey mid-stream: the OLD hotkey's events stop matching entirely")
    func switchingHotkeyStopsOldOneMatching() {
        // Right Option's own down-event, decoded against Left Command as
        // the NOW-configured hotkey, must not match — this is exactly the
        // scenario `HotkeyManager` has to guard against when the Settings
        // picker changes selection mid-hold.
        let result = HotkeyFlagsDecoder.decode(keyCode: rightOptionKeyCode, flags: HotkeyFlagsDecoder.deviceRightOptionMask, hotkey: .leftCommand)
        #expect(result == nil)
    }

    // MARK: - Tap-to-toggle companion pairing (2026-08-24 hotkey rework):
    // the chord's second key is whichever OTHER modifier shares the same
    // side as the configured primary hotkey, replacing the old hardcoded
    // `.rightCommand` (which silently broke tap-to-toggle whenever Right
    // Command itself was picked as the primary hotkey).

    @Test("Right Option's tap-to-toggle companion is Right Command")
    func rightOptionCompanionIsRightCommand() {
        #expect(HotkeyOption.rightOption.tapToggleCompanion == .rightCommand)
    }

    @Test("Right Command's tap-to-toggle companion is Right Option")
    func rightCommandCompanionIsRightOption() {
        #expect(HotkeyOption.rightCommand.tapToggleCompanion == .rightOption)
    }

    @Test("Left Option's tap-to-toggle companion is Left Command")
    func leftOptionCompanionIsLeftCommand() {
        #expect(HotkeyOption.leftOption.tapToggleCompanion == .leftCommand)
    }

    @Test("Left Command's tap-to-toggle companion is Left Option")
    func leftCommandCompanionIsLeftOption() {
        #expect(HotkeyOption.leftCommand.tapToggleCompanion == .leftOption)
    }

    @Test("no HotkeyOption is ever its own tap-to-toggle companion")
    func noOptionIsOwnCompanion() {
        for option in HotkeyOption.allCases {
            #expect(option.tapToggleCompanion != option)
        }
    }
}
