# Step 1 - Foundation, Security & Modeling

## Initial Projetc Structure

- Phoenix 1.8 project with LiveView
- SQLite database via `ecto_sqlite3`
- Authentication generated with `mix phx.gen.auth`
- Telemetry domain separated into contexts

## Architectural Decisions

- **SQLite** chosen for simplecity in development and ease os containerization (single file, no external server)
- **Default Phoenix authentication** was adopted to accelerate delivery while keeping secure defaults.
- The `nodes` table represents a mostly static sensor registry (unique identifier + location).
- The `node_metrics` table stores the latest known metric per node, optimized for frequent last state reads
- Unique index on `node_id` ensures each has only one record in `node_metrics`
- `last_payload` is stored as `text` (JSON) to preserve flexibility and keep compatibility with SQLite JSON functions.

## Data Model Explanation

### `users`

| Field                    | Description                  |
| ------------------------ | ---------------------------- |
| id                       | Primary key                  |
| email                    | Unique email used for login  |
| hashed_password          | bcrypt password hash         |
| confirmed_at             | Email confirmation timestamp |
| inserted_at / updated_at | Ecto timestamps              |

### `nodes`

| Field                    | Description              |
| ------------------------ | ------------------------ |
| id                       | Primary key              |
| machine_identifier       | Unique sensor identifier |
| location                 | Textual location         |
| inserted_at / updated_at | Ecto timestamps          |

### `node_metrics`

| Field                    | Description                                  |
| ------------------------ | -------------------------------------------- |
| id                       | Primary key                                  |
| node_id                  | FK to `nodes` (on delete cascade)            |
| status                   | String e.g., "online", "offline", "degraded" |
| total_events_processed   | Counter of total events processed            |
| last_payload             | JSON with the last raw payload               |
| last_seen_at             | Last datetime when a metric was received     |
| inserted_at / updated_at | Ecto timestamps                              |

This separation allows `nodes` to be mostly immutable (except location) while `node_metrics` is updated frequently without bloking reads of the statics registry.

## Operational Notes

- Database path is runtime-driven through `DATABASE_PATH`.
- Default local path is `./data/w_core.sqlite3`.
- For containers, mount `./.docker/volumes/db` to `/app/data` and set `DATABASE_PATH=/app/data/w_core.sqlite3`.
- On Windows, Phoenix/LiveView symlink warnings may appear; running the terminal at least once as Administrator helps reduce these issues.

## Executed Commands

```bash
mix phx.new w_core --live --database sqlite3
cd w_core
mix deps.get
mix phx.gen.auth Accounts User users
mix ecto.create && mix ecto.migrate
mix phx.gen.context Telemetry Node nodes machine_identifier:string:unique location:string
mix ecto.gen.migration create_node_metrics
# (manual editing of the migration)
mix ecto.migrate
```
