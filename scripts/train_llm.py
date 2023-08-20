import logging
import ray
import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--num-workers",
        type=int,
        default=2,
        help="Sets number of workers for training.",
    )
    args, _ = parser.parse_known_args()

    logging.info("===Ray training===")
    logging.info(f"===Workers: {args.num_workers}===")

    ray.init(address="auto")

    logging.info(ray.cluster_resources())
