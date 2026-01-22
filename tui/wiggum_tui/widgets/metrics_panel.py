"""Metrics panel widget showing aggregate dashboard from worker logs."""

from pathlib import Path
from dataclasses import dataclass, field
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical, Grid
from textual.widgets import Static
from textual.widget import Widget

from ..data.conversation_parser import parse_iteration_logs, get_conversation_summary
from ..data.worker_scanner import scan_workers
from ..data.models import WorkerStatus


@dataclass
class AggregateMetrics:
    """Aggregated metrics from all workers."""
    total_workers: int = 0
    running_workers: int = 0
    completed_workers: int = 0
    failed_workers: int = 0
    total_turns: int = 0
    total_tool_calls: int = 0
    total_cost_usd: float = 0.0
    total_duration_ms: int = 0
    total_tokens: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    cache_creation_tokens: int = 0
    cache_read_tokens: int = 0
    # Per-worker summaries for display
    worker_summaries: list[dict] = field(default_factory=list)


def aggregate_worker_metrics(ralph_dir: Path) -> AggregateMetrics:
    """Aggregate metrics from all worker logs.

    Args:
        ralph_dir: Path to .ralph directory.

    Returns:
        AggregateMetrics with totals from all workers.
    """
    metrics = AggregateMetrics()
    workers = scan_workers(ralph_dir)

    metrics.total_workers = len(workers)

    for worker in workers:
        if worker.status == WorkerStatus.RUNNING:
            metrics.running_workers += 1
        elif worker.status == WorkerStatus.COMPLETED:
            metrics.completed_workers += 1
        elif worker.status == WorkerStatus.FAILED:
            metrics.failed_workers += 1

        # Parse conversation logs for this worker
        worker_dir = ralph_dir / "workers" / worker.id
        conversation = parse_iteration_logs(worker_dir)
        summary = get_conversation_summary(conversation)

        metrics.total_turns += summary["turns"]
        metrics.total_tool_calls += summary["tool_calls"]
        metrics.total_cost_usd += summary["cost_usd"]
        metrics.total_duration_ms += summary["duration_ms"]
        metrics.total_tokens += summary["tokens"]

        # Aggregate token breakdown from results
        for result in conversation.results:
            metrics.input_tokens += result.usage.input
            metrics.output_tokens += result.usage.output
            metrics.cache_creation_tokens += result.usage.cache_creation
            metrics.cache_read_tokens += result.usage.cache_read

        # Store worker summary for display
        if summary["turns"] > 0 or summary["cost_usd"] > 0:
            metrics.worker_summaries.append({
                "worker_id": worker.id,
                "task_id": worker.task_id,
                "status": worker.status.value,
                "turns": summary["turns"],
                "tool_calls": summary["tool_calls"],
                "cost_usd": summary["cost_usd"],
                "duration_ms": summary["duration_ms"],
                "tokens": summary["tokens"],
            })

    # Sort by cost descending
    metrics.worker_summaries.sort(key=lambda x: x["cost_usd"], reverse=True)

    return metrics


def format_tokens(count: int) -> str:
    """Format token count for display."""
    if count >= 1_000_000:
        return f"{count / 1_000_000:.1f}M"
    elif count >= 1_000:
        return f"{count / 1_000:.1f}K"
    else:
        return str(count)


def format_cost(cost: float) -> str:
    """Format cost in USD."""
    return f"${cost:.2f}"


def format_duration(ms: int) -> str:
    """Format duration from milliseconds."""
    seconds = ms // 1000
    if seconds >= 3600:
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        return f"{hours}h {minutes}m"
    elif seconds >= 60:
        minutes = seconds // 60
        secs = seconds % 60
        return f"{minutes}m {secs}s"
    else:
        return f"{seconds}s"


class MetricCard(Static):
    """A single metric card."""

    DEFAULT_CSS = """
    MetricCard {
        background: #181825;
        border: solid #45475a;
        padding: 1;
        height: auto;
        min-height: 5;
    }

    MetricCard .metric-title {
        color: #7f849c;
        text-style: bold;
    }

    MetricCard .metric-value {
        color: #a6e3a1;
        text-style: bold;
    }

    MetricCard .metric-secondary {
        color: #a6adc8;
    }
    """

    def __init__(self, title: str, value: str, secondary: str = "") -> None:
        super().__init__()
        self.title = title
        self.value = value
        self.secondary = secondary

    def render(self) -> str:
        lines = [
            f"[#7f849c]{self.title}[/]",
            f"[bold #a6e3a1]{self.value}[/]",
        ]
        if self.secondary:
            lines.append(f"[#a6adc8]{self.secondary}[/]")
        return "\n".join(lines)


class MetricsPanel(Widget):
    """Metrics panel showing aggregated statistics from all worker logs."""

    DEFAULT_CSS = """
    MetricsPanel {
        height: 1fr;
        width: 100%;
        padding: 1;
        layout: vertical;
        overflow-y: auto;
    }

    MetricsPanel .metrics-grid {
        grid-size: 4;
        grid-gutter: 1;
        height: auto;
    }

    MetricsPanel .section-title {
        color: #cba6f7;
        text-style: bold;
        padding: 1 0;
    }

    MetricsPanel .empty-message {
        text-align: center;
        color: #7f849c;
        padding: 2;
    }

    MetricsPanel .workers-list {
        height: 1fr;
        border: solid #45475a;
        background: #1e1e2e;
        padding: 1;
    }

    MetricsPanel .worker-row {
        height: 1;
    }
    """

    def __init__(self, ralph_dir: Path) -> None:
        super().__init__()
        self.ralph_dir = ralph_dir
        self.metrics: AggregateMetrics = AggregateMetrics()
        self._last_data_hash: str = ""

    def _compute_data_hash(self, metrics: AggregateMetrics) -> str:
        """Compute a hash of metrics data for change detection."""
        data = (
            metrics.total_workers,
            metrics.completed_workers,
            metrics.failed_workers,
            metrics.total_cost_usd,
            metrics.total_turns,
            metrics.total_tool_calls,
        )
        return str(data)

    def compose(self) -> ComposeResult:
        self._load_metrics()

        if self.metrics.total_workers == 0:
            yield Static(
                "No workers found. Run workers to see metrics.",
                classes="empty-message",
            )
            return

        yield Static("SUMMARY", classes="section-title")
        with Grid(classes="metrics-grid"):
            success_rate = 0.0
            if self.metrics.completed_workers + self.metrics.failed_workers > 0:
                success_rate = self.metrics.completed_workers / (self.metrics.completed_workers + self.metrics.failed_workers) * 100

            yield MetricCard(
                "Workers",
                str(self.metrics.total_workers),
                f"{self.metrics.running_workers} running / {self.metrics.completed_workers} done / {self.metrics.failed_workers} failed",
            )
            yield MetricCard(
                "Success Rate",
                f"{success_rate:.1f}%",
                f"{self.metrics.completed_workers} of {self.metrics.completed_workers + self.metrics.failed_workers}",
            )
            yield MetricCard(
                "Total Time",
                format_duration(self.metrics.total_duration_ms),
                "",
            )
            yield MetricCard(
                "Total Cost",
                format_cost(self.metrics.total_cost_usd),
                "",
            )

        yield Static("CONVERSATION STATS", classes="section-title")
        with Grid(classes="metrics-grid"):
            yield MetricCard(
                "Total Turns",
                str(self.metrics.total_turns),
                f"{self.metrics.total_turns / max(1, self.metrics.total_workers):.1f} avg/worker",
            )
            yield MetricCard(
                "Tool Calls",
                str(self.metrics.total_tool_calls),
                f"{self.metrics.total_tool_calls / max(1, self.metrics.total_turns):.1f} avg/turn",
            )
            yield MetricCard(
                "Total Tokens",
                format_tokens(self.metrics.total_tokens),
                "",
            )
            yield MetricCard(
                "Cost/Worker",
                format_cost(self.metrics.total_cost_usd / max(1, self.metrics.total_workers)),
                "average",
            )

        yield Static("TOKEN BREAKDOWN", classes="section-title")
        with Grid(classes="metrics-grid"):
            yield MetricCard(
                "Input",
                format_tokens(self.metrics.input_tokens),
                "",
            )
            yield MetricCard(
                "Output",
                format_tokens(self.metrics.output_tokens),
                "",
            )
            yield MetricCard(
                "Cache Creation",
                format_tokens(self.metrics.cache_creation_tokens),
                "",
            )
            yield MetricCard(
                "Cache Read",
                format_tokens(self.metrics.cache_read_tokens),
                "",
            )

        if self.metrics.worker_summaries:
            yield Static("WORKERS BY COST", classes="section-title")
            with Vertical(classes="workers-list"):
                # Show top 10 workers by cost
                for worker in self.metrics.worker_summaries[:10]:
                    status_color = {
                        "running": "#a6e3a1",
                        "completed": "#89b4fa",
                        "failed": "#f38ba8",
                        "stopped": "#7f849c",
                    }.get(worker["status"], "#7f849c")

                    yield Static(
                        f"[{status_color}]{worker['status']:10}[/] │ "
                        f"[#cba6f7]{worker['task_id'][:25]:25}[/] │ "
                        f"[#7f849c]{worker['turns']:3} turns[/] │ "
                        f"[#7f849c]{worker['tool_calls']:4} tools[/] │ "
                        f"[#a6e3a1]{format_cost(worker['cost_usd'])}[/]",
                        classes="worker-row",
                    )

    def _load_metrics(self) -> None:
        """Load and aggregate metrics from all worker logs."""
        self.metrics = aggregate_worker_metrics(self.ralph_dir)

    def refresh_data(self) -> None:
        """Refresh metrics data and re-render only if data changed."""
        old_metrics = self.metrics
        self._load_metrics()

        # Check if data actually changed
        new_hash = self._compute_data_hash(self.metrics)
        if new_hash == self._last_data_hash:
            return  # No change, skip refresh
        self._last_data_hash = new_hash

        self.remove_children()
        for widget in self.compose():
            self.mount(widget)
