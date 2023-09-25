import boto3
import pickle
import logging
import ray
import argparse
from ray.air.config import RunConfig, ScalingConfig
from ray.train.xgboost import XGBoostTrainer

ray.init(address="auto")
bucket = "fm-ops-datasets"
prefix = "model"


def prepare_dataset():
    dataset = ray.data.read_csv(f"s3://{bucket}/training/demo.csv")

    train_dataset, valid_dataset = dataset.train_test_split(test_size=0.3)
    test_dataset = valid_dataset.drop_columns(cols=["Target"])

    return train_dataset, valid_dataset, test_dataset


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
    logging.info(ray.cluster_resources())

    train_dataset, valid_dataset, test_dataset = prepare_dataset()

    trainer = XGBoostTrainer(
        scaling_config=ScalingConfig(
            num_workers=args.num_workers,
            use_gpu=False,
            _max_cpu_fraction_per_node=0.9,
        ),
        run_config=RunConfig(
            name="training_demo", storage_path=f"s3://{bucket}/{prefix}"
        ),
        label_column="Target",
        num_boost_round=20,
        params={
            "objective": "binary:logistic",
            "eval_metric": ["logloss", "error"],
        },
        datasets={"train": train_dataset, "valid": valid_dataset},
    )

    model = trainer.fit()
    logging.info(model.metrics)

    pickle_obj = pickle.dumps(model.checkpoint)
    s3_resource = boto3.resource("s3")
    s3_resource.Object(bucket, f"{prefix}/model.pkl").put(Body=pickle_obj)

    ray.shutdown()
