"""Reorder identical task/reference blocks for a frozen context stress test."""


def render_context_task(task, context):
    if context is None:
        return task
    parts, position = context.get("parts"), context.get("position")
    if (not isinstance(parts, list) or len(parts) != 2
            or not all(isinstance(part, str) for part in parts)
            or position not in ["beginning", "middle", "end"]):
        raise ValueError("context treatment requires two text parts and a declared position")
    archive = [f'<reference_archive part="{index + 1}">\n{part}\n</reference_archive>'
               for index, part in enumerate(parts)]
    request = "<task>\n" + task + "\n</task>"
    blocks = {"beginning": [request, *archive], "middle": [archive[0], request, archive[1]],
              "end": [*archive, request]}
    return "\n\n".join(blocks[position])
