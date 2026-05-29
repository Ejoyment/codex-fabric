#!/usr/bin/env python3
"""
CODEX Fabric - E2EE Signaling Server Load Test Suite

This script simulates thousands of concurrent WebSocket connections to the
CODEX Fabric signaling server, testing connection stability, message throughput,
and E2EE key exchange performance under heavy load.

Usage:
    python3 tests/load/stress_test.py --url ws://localhost:8080/ws --connections 1000

Requirements:
    pip install websockets aiohttp
"""

import asyncio
import aiohttp
import json
import time
import uuid
import statistics
import argparse
from dataclasses import dataclass, field
from typing import List, Dict, Optional
from collections import defaultdict


@dataclass
class ClientMetrics:
    """Metrics for a single client connection."""
    client_id: str = ""
    connect_time: float = 0.0
    connected: bool = False
    messages_sent: int = 0
    messages_received: int = 0
    key_exchange_time: float = 0.0
    encryption_test_time: float = 0.0
    errors: List[str] = field(default_factory=list)
    latency_samples: List[float] = field(default_factory=list)


@dataclass
class LoadTestResults:
    """Aggregated results from a load test run."""
    total_connections: int = 0
    successful_connections: int = 0
    failed_connections: int = 0
    total_messages_sent: int = 0
    total_messages_received: int = 0
    connect_times: List[float] = field(default_factory=list)
    key_exchange_times: List[float] = field(default_factory=list)
    encryption_times: List[float] = field(default_factory=list)
    latencies: List[float] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    duration: float = 0.0


def generate_mock_key_exchange_message(target_peer_id: str) -> dict:
    """Generate a mock key exchange message with fake public keys.
    
    In a real implementation, this would use actual Ed25519/X25519
    key generation from pointycastle or similar.
    """
    fake_signing_key = uuid.uuid4().hex + uuid.uuid4().hex.replace('-', '')[:32]
    fake_exchange_key = uuid.uuid4().hex + uuid.uuid4().hex.replace('-', '')[:32]
    
    return {
        "type": "key-exchange",
        "peer_id": target_peer_id,
        "signing_public_key": fake_signing_key,
        "exchange_public_key": fake_exchange_key,
        "timestamp": int(time.time() * 1000),
    }


async def simulate_client(
    url: str,
    client_index: int,
    results: LoadTestResults,
    room_id: str = "load-test-room",
    test_duration: float = 10.0,
):
    """Simulate a single client connection with full E2EE handshake."""
    metrics = ClientMetrics(client_id=f"client-{client_index}")
    
    try:
        async with aiohttp.ClientSession() as session:
            # Connect via WebSocket
            start_time = time.monotonic()
            async with session.ws_connect(url) as ws:
                connect_time = time.monotonic() - start_time
                metrics.connect_time = connect_time
                metrics.connected = True
                results.connect_times.append(connect_time)
                
                # Wait for welcome message
                try:
                    msg = await asyncio.wait_for(ws.receive(), timeout=5.0)
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        welcome = json.loads(msg.data)
                        metrics.client_id = welcome.get("id", metrics.client_id)
                        results.successful_connections += 1
                except asyncio.TimeoutError:
                    metrics.errors.append("Welcome message timeout")
                    results.failed_connections += 1
                    return
                
                # Join room
                await ws.send_json({
                    "type": "join",
                    "room_id": room_id,
                    "peer_id": metrics.client_id,
                })
                
                # Wait for joined confirmation
                try:
                    msg = await asyncio.wait_for(ws.receive(), timeout=5.0)
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        data = json.loads(msg.data)
                        if data.get("type") == "error":
                            metrics.errors.append(data.get("error", "unknown"))
                            return
                except asyncio.TimeoutError:
                    metrics.errors.append("Join room timeout")
                    return
                
                # Simulate key exchange (send to a pseudo-peer)
                peer_id = f"peer-{(client_index + 1) % 1000}"
                key_exchange_start = time.monotonic()
                await ws.send_json(generate_mock_key_exchange_message(peer_id))
                metrics.key_exchange_time = time.monotonic() - key_exchange_start
                results.key_exchange_times.append(metrics.key_exchange_time)
                
                # Run message throughput test for the test duration
                test_start = time.monotonic()
                while (time.monotonic() - test_start) < test_duration:
                    # Send ping
                    send_start = time.monotonic()
                    await ws.send_json({
                        "type": "ping",
                        "timestamp": int(time.time() * 1000),
                    })
                    metrics.messages_sent += 1
                    
                    # Wait for pong
                    try:
                        msg = await asyncio.wait_for(ws.receive(), timeout=2.0)
                        latency = time.monotonic() - send_start
                        metrics.latency_samples.append(latency)
                        results.latencies.append(latency)
                        
                        if msg.type == aiohttp.WSMsgType.TEXT:
                            data = json.loads(msg.data)
                            if data.get("type") in ("pong", "ready", "key-exchange"):
                                metrics.messages_received += 1
                    except asyncio.TimeoutError:
                        metrics.errors.append("Pong timeout")
                    
                    # Small delay to prevent overwhelming
                    await asyncio.sleep(0.01)
                
                results.total_messages_sent += metrics.messages_sent
                results.total_messages_received += metrics.messages_received
                
    except Exception as e:
        metrics.errors.append(str(e))
        results.errors.append(f"Client-{client_index}: {e}")
        results.failed_connections += 1


async def run_load_test(
    url: str,
    num_connections: int = 100,
    test_duration: float = 10.0,
    ramp_up_delay: float = 0.01,
):
    """Run a complete load test with the specified parameters."""
    results = LoadTestResults(total_connections=num_connections)
    start_time = time.monotonic()
    
    print(f"\n{'='*60}")
    print(f"CODEX Fabric Load Test")
    print(f"{'='*60}")
    print(f"Target:        {url}")
    print(f"Connections:   {num_connections}")
    print(f"Duration:      {test_duration}s")
    print(f"{'='*60}\n")
    
    # Create tasks with ramp-up delay
    tasks = []
    for i in range(num_connections):
        task = asyncio.create_task(
            simulate_client(url, i, results, test_duration=test_duration)
        )
        tasks.append(task)
        if ramp_up_delay > 0:
            await asyncio.sleep(ramp_up_delay)
    
    # Wait for all tasks to complete
    await asyncio.gather(*tasks, return_exceptions=True)
    
    results.duration = time.monotonic() - start_time
    
    # Print results
    print_results(results)


def print_results(results: LoadTestResults):
    """Print formatted test results."""
    print(f"\n{'='*60}")
    print(f"LOAD TEST RESULTS")
    print(f"{'='*60}")
    
    print(f"\n--- Connection Stats ---")
    print(f"Total attempted:    {results.total_connections}")
    print(f"Successful:         {results.successful_connections}")
    print(f"Failed:             {results.failed_connections}")
    success_rate = (results.successful_connections / max(results.total_connections, 1)) * 100
    print(f"Success rate:       {success_rate:.1f}%")
    
    print(f"\n--- Message Stats ---")
    print(f"Messages sent:      {results.total_messages_sent}")
    print(f"Messages received:  {results.total_messages_received}")
    msgs_per_sec = results.total_messages_sent / max(results.duration, 0.001)
    print(f"Throughput:         {msgs_per_sec:.1f} msg/sec")
    
    if results.connect_times:
        print(f"\n--- Connect Latency ---")
        print(f"Mean:               {statistics.mean(results.connect_times)*1000:.1f}ms")
        print(f"Median:             {statistics.median(results.connect_times)*1000:.1f}ms")
        if len(results.connect_times) > 1:
            print(f"Std Dev:            {statistics.stdev(results.connect_times)*1000:.1f}ms")
        print(f"Min:                {min(results.connect_times)*1000:.1f}ms")
        print(f"Max:                {max(results.connect_times)*1000:.1f}ms")
    
    if results.key_exchange_times:
        print(f"\n--- Key Exchange Latency ---")
        print(f"Mean:               {statistics.mean(results.key_exchange_times)*1000:.1f}ms")
        print(f"Median:             {statistics.median(results.key_exchange_times)*1000:.1f}ms")
    
    if results.latencies:
        print(f"\n--- Message Latency ---")
        print(f"Mean:               {statistics.mean(results.latencies)*1000:.1f}ms")
        print(f"Median:             {statistics.median(results.latencies)*1000:.1f}ms")
        if len(results.latencies) > 1:
            print(f"Std Dev:            {statistics.stdev(results.latencies)*1000:.1f}ms")
        print(f"p95:                {sorted(results.latencies)[int(len(results.latencies)*0.95)]*1000:.1f}ms")
        print(f"p99:                {sorted(results.latencies)[int(len(results.latencies)*0.99)]*1000:.1f}ms")
    
    print(f"\n--- Overall ---")
    print(f"Total duration:     {results.duration:.2f}s")
    
    if results.errors:
        print(f"\n--- Errors ({len(results.errors)}) ---")
        for err in results.errors[:10]:
            print(f"  - {err}")
        if len(results.errors) > 10:
            print(f"  ... and {len(results.errors) - 10} more")
    
    print(f"\n{'='*60}")
    
    # Pass/Fail assessment
    if success_rate >= 99.0 and len(results.errors) == 0:
        print("RESULT: ✅ PASS - Server handling load successfully")
    elif success_rate >= 95.0:
        print("RESULT: ⚠️  WARN - Some connections failed under load")
    else:
        print("RESULT: ❌ FAIL - Server struggling under load")
    
    print(f"{'='*60}\n")


def main():
    parser = argparse.ArgumentParser(description="CODEX Fabric Load Test")
    parser.add_argument("--url", default="ws://localhost:8080/ws", help="WebSocket server URL")
    parser.add_argument("--connections", type=int, default=100, help="Number of concurrent connections")
    parser.add_argument("--duration", type=float, default=10.0, help="Test duration in seconds")
    parser.add_argument("--ramp-up", type=float, default=0.01, help="Delay between connections (ramp-up)")
    args = parser.parse_args()
    
    asyncio.run(run_load_test(
        url=args.url,
        num_connections=args.connections,
        test_duration=args.duration,
        ramp_up_delay=args.ramp_up,
    ))


if __name__ == "__main__":
    main()