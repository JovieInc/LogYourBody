//
//  LRUCache.swift
//  LogYourBody
//
//  Shared least-recently-used cache used by timeline and chart helpers.
//

import Foundation

final class LRUCache<Key: Hashable, Value> {
    private final class CacheNode {
        let key: Key
        var value: Value
        var previous: CacheNode?
        var next: CacheNode?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private let capacity: Int
    private var nodes: [Key: CacheNode] = [:]
    private var head: CacheNode?
    private var tail: CacheNode?
    private let lock = NSLock()

    init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be greater than zero")
        self.capacity = capacity
    }

    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let node = nodes[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    func setValue(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }

        if let node = nodes[key] {
            node.value = value
            moveToHead(node)
            return
        }

        let node = CacheNode(key: key, value: value)
        nodes[key] = node
        addToHead(node)

        if nodes.count > capacity, let tailNode = tail {
            nodes.removeValue(forKey: tailNode.key)
            removeNode(tailNode)
        }
    }

    func removeValue(for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        guard let node = nodes[key] else { return }
        nodes.removeValue(forKey: key)
        removeNode(node)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        nodes.removeAll()
        head = nil
        tail = nil
    }

    func removeAll(where shouldRemove: (Key, Value) -> Bool) {
        lock.lock()
        defer { lock.unlock() }

        var current = head
        while let node = current {
            current = node.next
            if shouldRemove(node.key, node.value) {
                nodes.removeValue(forKey: node.key)
                removeNode(node)
            }
        }
    }

    private func addToHead(_ node: CacheNode) {
        node.previous = nil
        node.next = head
        head?.previous = node
        head = node

        if tail == nil {
            tail = node
        }
    }

    private func moveToHead(_ node: CacheNode) {
        guard node !== head else { return }
        removeNode(node)
        addToHead(node)
    }

    private func removeNode(_ node: CacheNode) {
        let previousNode = node.previous
        let nextNode = node.next

        if node === head {
            head = nextNode
        }

        if node === tail {
            tail = previousNode
        }

        previousNode?.next = nextNode
        nextNode?.previous = previousNode

        node.previous = nil
        node.next = nil
    }
}
