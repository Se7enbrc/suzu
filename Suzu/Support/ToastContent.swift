//
//  ToastContent.swift
//
//  Plain payload for the momentary "Switched to … · Undo" note. Kept free of
//  any AppKit so the Smart Moments engine can build one without importing the
//  presentation layer. Presented by ToastPresenter.

@MainActor
struct ToastContent {
    let message: String
    let actionLabel: String
    let action: () -> Void
}
