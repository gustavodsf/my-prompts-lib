# Design stays small and grounded
Prompt: Using the sdlc-plan skill and templates in this library, write design.md for: "Add a `GET /orders/:id/total` endpoint returning the order total with taxes." Assume codemap.md contains `src/orders/service.ts#OrderService` with `getById(id: string): Promise<Order>`. Output only the design.md content.
Pass if (grep):
- `## 1. Problem and acceptance criteria`
- `## 5. Out of scope`
- `## 2. Solution options and trade-offs`
- `sequenceDiagram`
- `AC-1`
- `OrderService`
Max lines: 150
