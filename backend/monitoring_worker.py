import time
import traceback

from backend import monitor_active_checkouts


def main():
    print("🚀 Proactive monitoring worker started")

    while True:
        try:
            monitor_active_checkouts()

        except Exception as e:
            print(
                f"❌ Monitoring worker error: "
                f"{type(e).__name__}: {e}"
            )
            traceback.print_exc()

        # Run every 60 seconds in production.
        time.sleep(60)


if __name__ == "__main__":
    main()