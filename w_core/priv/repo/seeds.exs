# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias WCore.Accounts.User
alias WCore.Repo
alias WCore.Telemetry.Node
alias WCore.Telemetry.NodeMetrics
alias WCore.Telemetry.TelemetryEvent

import Ecto.Query

machine_count = 35

status_distribution =
	List.duplicate("online", 18) ++
		List.duplicate("degraded", 9) ++
		List.duplicate("offline", 6) ++
		List.duplicate("unknown", 2)

locations = [
	"Line A",
	"Line B",
	"Line C",
	"Line D",
	"North Wing",
	"South Wing",
	"Bay 1",
	"Bay 2",
	"Bay 3",
	"Warehouse"
]

error_types = [
	"network_timeout",
	"sensor_malfunction",
	"power_drop",
	"hydraulic_leak",
	"temperature_spike",
	"firmware_fault"
]

error_messages = [
	"Network timeout while reading telemetry bus",
	"Sensor drift detected above threshold",
	"Power voltage outside operational bounds",
	"Hydraulic pressure unstable in manifold",
	"Temperature critical alert on chamber",
	"Firmware exception while processing cycle"
]

seed_user_email = System.get_env("SEED_USER_EMAIL")

user_query =
	case seed_user_email do
		nil ->
			from(u in User, order_by: [desc: u.id], limit: 1)

		email ->
			from(u in User, where: u.email == ^email, order_by: [desc: u.id], limit: 1)
	end

case Repo.one(user_query) do
	nil ->
		IO.puts("[seeds] No users found. Register a user first and run seeds again.")

	user ->
		prefix = "demo-#{user.id}-machine-"

		machine_identifiers =
			1..machine_count
			|> Enum.map(fn i ->
				"#{prefix}#{String.pad_leading(Integer.to_string(i), 2, "0")}"
			end)

		existing_nodes =
			from(n in Node,
				where: n.user_id == ^user.id,
				where: n.machine_identifier in ^machine_identifiers
			)
			|> Repo.all()
			|> Map.new(&{&1.machine_identifier, &1})

		now = DateTime.utc_now() |> DateTime.truncate(:second)

		inserted_or_updated_nodes =
			machine_identifiers
			|> Enum.with_index(1)
			|> Enum.map(fn {machine_identifier, index} ->
				location = Enum.at(locations, rem(index - 1, length(locations)))

				case Map.get(existing_nodes, machine_identifier) do
					nil ->
						%Node{}
						|> Node.changeset(
							%{machine_identifier: machine_identifier, location: location},
							%{user: user}
						)
						|> Repo.insert!()

					node ->
						node
						|> Ecto.Changeset.change(location: location)
						|> Repo.update!()
				end
			end)

		metrics_rows =
			inserted_or_updated_nodes
			|> Enum.with_index(1)
			|> Enum.map(fn {node, index} ->
				status = Enum.at(status_distribution, index - 1)
				seen_at = DateTime.add(now, -(index * 180), :second)

				payload_base = %{
					"machine_identifier" => node.machine_identifier,
					"temperature_c" => 60 + rem(index * 3, 25),
					"rpm" => 900 + rem(index * 137, 2200),
					"vibration_mm_s" => Float.round(0.6 + rem(index * 17, 40) / 10, 2)
				}

				payload =
					case status do
						"offline" ->
							error_index = rem(index - 1, length(error_types))

							Map.merge(payload_base, %{
								"error_type" => Enum.at(error_types, error_index),
								"error_message" => Enum.at(error_messages, error_index),
								"severity" => "critical"
							})

						"degraded" ->
							error_index = rem(index + 1, length(error_types))

							Map.merge(payload_base, %{
								"error_type" => Enum.at(error_types, error_index),
								"error_message" => Enum.at(error_messages, error_index),
								"severity" => "warning"
							})

						"unknown" ->
							Map.put(payload_base, "note", "Awaiting first heartbeat")

						_ ->
							Map.put(payload_base, "note", "Operational")
					end

				%{
					node_id: node.id,
					status: status,
					total_events_processed: 120 + index * 11,
					last_payload: payload,
					last_seen_at: seen_at,
					inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
					updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
				}
			end)

		Repo.insert_all(NodeMetrics, metrics_rows,
			on_conflict: {:replace, [:status, :total_events_processed, :last_payload, :last_seen_at, :updated_at]},
			conflict_target: [:node_id]
		)

		# Keep events idempotent for this demo dataset.
		Repo.delete_all(from(e in TelemetryEvent, where: e.machine_identifier in ^machine_identifiers))

		telemetry_rows =
			inserted_or_updated_nodes
			|> Enum.with_index(1)
			|> Enum.flat_map(fn {node, index} ->
				status = Enum.at(status_distribution, index - 1)

				Enum.map(0..4, fn offset ->
					occurred_at = DateTime.add(now, -((index * 300) + offset * 45), :second)

					event_status =
						case {status, offset} do
							{"online", 0} -> "degraded"
							{"online", 1} -> "online"
							{"online", _} -> "online"
							{"unknown", _} -> "unknown"
							{current_status, _} -> current_status
						end

					error_index = rem(index + offset, length(error_types))
					is_error = event_status in ["offline", "degraded"]
					resolved = is_error and rem(offset + index, 3) == 0

					payload = %{
						"error_type" => Enum.at(error_types, error_index),
						"error_message" => Enum.at(error_messages, error_index),
						"batch" => "seed",
						"sequence" => offset + 1
					}

					%{
						machine_identifier: node.machine_identifier,
						status: event_status,
						payload: payload,
						error_message: if(is_error, do: Enum.at(error_messages, error_index), else: nil),
						occurred_at: occurred_at,
						processed_at: DateTime.add(occurred_at, 15, :second),
						resolved_at:
							if(resolved,
								do: DateTime.add(occurred_at, 300, :second),
								else: nil
							),
						inserted_at: now,
						updated_at: now
					}
				end)
			end)

		Repo.insert_all(TelemetryEvent, telemetry_rows)

		status_counts =
			status_distribution
			|> Enum.frequencies()
			|> Enum.map(fn {status, count} -> "#{status}=#{count}" end)
			|> Enum.join(", ")

		IO.puts("[seeds] Telemetry dataset ready for #{user.email}.")
		IO.puts("[seeds] Nodes: #{machine_count}, Events: #{length(telemetry_rows)}")
		IO.puts("[seeds] Status distribution: #{status_counts}")
end
