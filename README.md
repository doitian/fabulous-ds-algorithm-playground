# Fabulous DS & Algorithm Playground

Zig exercises for *Fabulous Adventures in Data Structures and Algorithms* (Eric Lippert).
Each exercise has a skeleton with `@panic("TODO")` bodies and a test file. You fill in the skeleton until the tests pass.

## Setup

Zig is pinned in `mise.toml` (0.17.0):

```bash
mise install
```

## Workflow

```bash
mise exec -- zig build test
```

A test that hits a `TODO` panic is reported as a crash, and the runner moves on to the next test. To run a subset, filter by test name (repeatable):

```bash
mise exec -- zig build test -Dtest-filter=ImStack
```

To open the language reference bundled with the pinned Zig version (works offline):

```bash
mise run langref
```

## Layout

```
src/
  root.zig                 module root; pulls every test file in
  chNN/<name>.zig          skeleton — your implementation goes here
  chNN/<name>_test.zig     tests — read them as the spec
```

## Conventions

- **Errors instead of exceptions.** If the book throws `InvalidOperationException`, the Zig version returns an error, e.g. `error.EmptyStack`.
- **Allocators are passed in.** Operations that create nodes take an `std.mem.Allocator`. Persistent structures share nodes between versions, so nodes aren't freed one at a time. The caller owns their lifetime, and the tests use an `ArenaAllocator`.
- **`IEnumerable<T>` becomes an iterator.** `iterator()` returns a struct whose `next() ?T` yields items.
- **You choose the representation.** The skeletons fix only the public API. Add whatever fields you like, and keep `empty` consistent with them.

## Progress

| Chapter | Exercise | Skeleton | Status |
| --- | --- | --- | --- |
| 2.2 | Immutable stack | `src/ch02/im_stack.zig` | ✅ |
| 2.4 | Stack `reverse` (listing 2.7) | `src/ch02/im_stack.zig` | ✅ |
| 2.4 | Immutable queue | `src/ch02/im_queue.zig` | ✅ |
| 2.7 | Stack `reverseOnto`, `concatenate`, `append` (listing 2.13) | `src/ch02/im_stack.zig` | ✅ |
| 2.7 | Hughes list | `src/ch02/hughes_list.zig` | ✅ |
| 3.3.1 | Mini-deque (listing 3.4) | `src/ch03/mini_deque.zig` | ✅ |
| 3.3–3.5 | Immutable finger-tree deque (listing 3.5) | `src/ch03/im_deque.zig` | ✅ |
| 3.7 | Deque concatenation (stretch goal) | `src/ch03/im_deque.zig` | ✅ |

## Chapter 3 exercise

1. Implement `MiniDeque(T)`: immutable buffers of one to four items. Run `mise exec -- zig build test -Dtest-filter=MiniDeque`.
2. Implement `ImDeque(T)` through iteration. Use nonempty end buffers and a recursive middle containing three-item chunks. Run `mise exec -- zig build test -Dtest-filter="ImDeque:"`.
3. Implement the concatenation stretch goal from section 3.7, allowing two- and three-item middle chunks. Run `mise exec -- zig build test -Dtest-filter="ImDeque concatenate:"`.

The deque uses runtime recursive nodes to express the middle's increasing depth. Iteration takes O(n) total time and O(log n) scratch space, allocated when the iterator is created. Concatenation joins only the boundary digits and recursive middles, preserving shared interior subtrees. Allocation tests check persistence-friendly space growth without requiring a particular node layout; they do not prove the time bounds.

## License

[Mozilla Public License 2.0](LICENSE)
