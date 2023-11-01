from ray import serve
from starlette.requests import Request


@serve.deployment(ray_actor_options={"num_gpus": 1})
class PredictDeployment:
    def __init__(self, model_id: str):
        from transformers import (
            AutoModelForCausalLM,
            AutoTokenizer,
            GenerationConfig,
        )
        import torch

        self.model = AutoModelForCausalLM.from_pretrained(
            model_id,
            trust_remote_code=True,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True,
        ).cuda()

        self.tokenizer = AutoTokenizer.from_pretrained(model_id)

        self.config = GenerationConfig(
            temperature=0.7,
            top_p=0.9,
            num_beams=4,
            include_prompt_in_result=False,
        )

    def generate(self, prompt, params):
        inputs = self.tokenizer(prompt, return_tensors="pt")
        input_ids = inputs.input_ids.to(self.model.device)
        self.config.temperature = params["temperature"]
        self.config.top_p = params["top_p"]
        self.config.num_beams = params["num_beams"]

        generation_output = self.model.generate(
            input_ids,
            generation_config=self.config,
            max_new_tokens=params["max_tokens"],
            return_dict_in_generate=True,
            output_scores=False,
        )

        answer = []
        for seq in generation_output.sequences:
            output = self.tokenizer.decode(seq, skip_special_tokens=True)
            answer.append(output.split("### Answer:")[-1].strip())

        return answer[0]

    async def __call__(self, http_request: Request) -> str:
        json_request: str = await http_request.json()
        prompt = json_request["prompt"]
        params = json_request["params"]
        return self.generate(prompt, params)


# Deploy
nonfinetuned = PredictDeployment.bind(model_id="tiiuae/falcon-7b")
