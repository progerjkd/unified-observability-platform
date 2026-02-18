#!/usr/bin/env python3
"""
Generate all architecture diagrams for the Unified Observability Platform
"""

import subprocess
import sys
import os

# List of diagram scripts to execute
DIAGRAMS = [
    "aws_infrastructure.py",
    "data_flow.py",
    "eks_cluster.py",
    "network_architecture.py",
]

def main():
    """Execute all diagram generation scripts"""
    print("=" * 60)
    print("Generating Architecture Diagrams")
    print("=" * 60)

    # Change to the diagrams directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    failed = []

    for diagram in DIAGRAMS:
        print(f"\n📊 Generating {diagram}...")
        try:
            result = subprocess.run(
                [sys.executable, diagram],
                check=True,
                capture_output=True,
                text=True
            )
            print(f"✅ Generated {diagram.replace('.py', '.png')}")
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to generate {diagram}")
            print(f"Error: {e.stderr}")
            failed.append(diagram)

    print("\n" + "=" * 60)
    if failed:
        print(f"❌ {len(failed)} diagram(s) failed:")
        for f in failed:
            print(f"   - {f}")
        sys.exit(1)
    else:
        print(f"✅ Successfully generated {len(DIAGRAMS)} diagrams")
        print("\nOutput files:")
        for diagram in DIAGRAMS:
            png_file = diagram.replace('.py', '.png')
            print(f"   - {png_file}")
    print("=" * 60)

if __name__ == "__main__":
    main()
