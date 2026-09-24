pragma Singleton

import QtQuick

QtObject {
    id: theme

    // ─────────────────────────────────────────────
    // KAIROS THEME TOKENS
    //
    // Central visual identity. The shell reads all
    // color / font / geometry / motion values from
    // here. Reskin KAIROS by editing this file only.
    // ─────────────────────────────────────────────

    // SURFACES
    readonly property color background: "#08090B"
    readonly property color surface: "#101114"
    readonly property color surfaceAlt: "#15161A"
    readonly property color raised: "#1A1C21"

    // LINES
    readonly property color line: "#303238"
    readonly property color lineSoft: "#222429"
    readonly property color lineStrong: "#4A4D55"

    // TEXT
    readonly property color text: "#E0E0E3"
    readonly property color textBright: "#F2F2F4"
    readonly property color muted: "#686B73"
    readonly property color subtle: "#3F4249"
    readonly property color faint: "#2A2C32"

    // STATE / ACCENT
    readonly property color accent: "#8B87C7"
    readonly property color accentDim: "#5C5982"
    readonly property color ok: "#7EBB92"
    readonly property color warning: "#C9A24B"
    readonly property color critical: "#C9524D"

    // ─────────────────────────────────────────────
    // TYPOGRAPHY
    // ─────────────────────────────────────────────

    readonly property string fontMono: "Fira Code, DejaVu Sans Mono, Liberation Mono, monospace"
    readonly property string fontCondensed: "DejaVu Sans Condensed, Liberation Sans Narrow, sans-serif"

    // Sizes
    readonly property int sizeTitle: 13
    readonly property int sizeValue: 11
    readonly property int sizeLabel: 9
    readonly property int sizeMicro: 8

    // Tracking (px added between letters)
    readonly property int trackTitle: 4
    readonly property int trackLabel: 2
    readonly property int trackMicro: 1

    // ─────────────────────────────────────────────
    // GEOMETRY
    // ─────────────────────────────────────────────

    readonly property int radius: 0
    readonly property int borderWidth: 1
    readonly property int spacing: 18
    readonly property int gutSpacing: 26

    // ─────────────────────────────────────────────
    // MOTION
    // ─────────────────────────────────────────────

    readonly property int animationFast: 120
    readonly property int animationNormal: 220
    readonly property int animationSlow: 480
    readonly property bool reducedMotion: false

    // Easing: mechanical / restrained, no bounce.
    readonly property int easing: Easing.OutCubic
}