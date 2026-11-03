# Design stays small and grounded
Prompt: Using the sdlc-plan skill and templates in this library, write design.md for: "Add a `GET /orders/:id/total` endpoint returning the order total with taxes." Assume codemap.md contains `src/orders/service.ts#OrderService` with `getById(id: string): Promise<Order>`. Output only the design.md content.
Pass if (grep):
- `## 1. Problem and acceptance criteria`
- `## 4. Out of scope`
- `sequenceDiagram`
- `AC-1`
- `OrderService`
Max lines: 150
