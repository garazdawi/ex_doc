defmodule ExDoc.Formatter.MAN do
  @moduledoc false

  alias __MODULE__.Templates

  def run(config, project_nodes, extras) when is_map(config) do
    File.mkdir_p!(config.output)

    {modules, tasks} =
      project_nodes
      |> Enum.filter(&(&1.source_format == "text/markdown"))
      |> Enum.split_with(&(&1.type != :task))

    all_files =
      case config.man do
        :all -> generate_list(config, modules) ++ generate_list(config, tasks)
        :tasks -> generate_list(config, tasks)
        false -> []
      end ++ generate_extras(config, extras)

    all_files = List.flatten(all_files)
    entrypoint = man_entrypoint(config, all_files)
    %{entrypoint: entrypoint, build: all_files}
  end

  defp man_entrypoint(_config, []), do: ""

  defp man_entrypoint(config, [first | _]) do
    config.output |> Path.join(first) |> Path.relative_to_cwd()
  end

  defp generate_list(config, nodes) do
    nodes
    |> Task.async_stream(&generate_module(config, &1), timeout: :infinity)
    |> Enum.map(&elem(&1, 1))
  end

  defp generate_module(config, module_node) do
    section = if module_node.type == :task, do: "1", else: "3"
    filename = "#{module_node.id}.#{section}"

    config
    |> Templates.module_template(module_node)
    |> normalize_output()
    |> then(&write!(config, filename, &1))

    filename
  end

  defp generate_extras(config, extras) do
    for %ExDoc.ExtraNode{} = extra <- extras,
        section = extra.options[:man_section],
        section != nil do
      section = to_string(section)
      filename = "#{extra.id}.#{section}"

      config
      |> Templates.extra_template(extra, section)
      |> normalize_output()
      |> then(&write!(config, filename, &1))

      filename
    end
  end

  defp normalize_output(output) do
    output
    |> String.replace("\r\n", "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
  end

  defp write!(config, filename, content) do
    config.output
    |> Path.join(filename)
    |> File.write!(content)
  end
end
