#!/usr/bin/env python3
"""Minimal web UI for GPT-OSS-20B model comparison"""

from pathlib import Path

from flask import Flask, jsonify, request
from model_inference import get_inference, logger

app = Flask(__name__)
inference = get_inference()  # Loads ComparisonInference (2 GPUs)

# Load HTML template from same directory
HTML_PATH = Path(__file__).parent / "index.html"
HTML_TEMPLATE = HTML_PATH.read_text()


@app.route("/")
def index():
    return HTML_TEMPLATE


@app.route("/compare", methods=["POST"])
def compare():
    try:
        data = request.json
        lang = data.get("reasoning_language")
        prompt = data.get("prompt")
        baseline_prefix = data.get(
            "baseline_prefix", ""
        )  # Additional text for baseline

        if not lang or not prompt:
            return jsonify({"error": "Missing data"}), 400

        logger.info(f"Comparing: {lang}")

        # Generate responses and capture prompts used (increased token limit significantly)
        finetuned_result = inference.generate(
            prompt=prompt,
            reasoning_language=lang,
            model="finetuned",
            max_new_tokens=4096,
        )

        # For baseline, prepend custom prefix if provided
        baseline_prompt = (
            f"{baseline_prefix} {prompt}".strip() if baseline_prefix else prompt
        )
        baseline_result = inference.generate(
            prompt=baseline_prompt,
            reasoning_language=lang,
            model="baseline",
            max_new_tokens=4096,
        )

        # Debug: log raw outputs
        logger.info(
            f"Fine-tuned raw output (first 500 chars): {finetuned_result[:500]}"
        )
        logger.info(f"Baseline raw output (first 500 chars): {baseline_result[:500]}")

        # Parse reasoning tokens and final answer for each model
        def parse_response(text, model_type="finetuned"):
            # For fine-tuned model: extract from channel tags
            if model_type == "finetuned":
                reasoning = ""
                answer = ""

                # Extract analysis channel (reasoning)
                analysis_start_tag = "<|channel|>analysis<|message|>"
                if analysis_start_tag in text:
                    start = text.find(analysis_start_tag) + len(analysis_start_tag)
                    # Look for end tag - could be <|end|> or next channel
                    end_tag = text.find("<|end|>", start)
                    next_channel = text.find("<|channel|>", start)

                    if end_tag != -1:
                        if next_channel != -1 and next_channel < end_tag:
                            reasoning = text[start:next_channel].strip()
                        else:
                            reasoning = text[start:end_tag].strip()
                    elif next_channel != -1:
                        reasoning = text[start:next_channel].strip()
                    else:
                        reasoning = text[start:].strip()

                # Extract final channel (answer)
                final_start_tag = "<|channel|>final<|message|>"
                if final_start_tag in text:
                    start = text.find(final_start_tag) + len(final_start_tag)
                    # Look for end tag - could be <|return|> or <|end|>
                    return_tag = text.find("<|return|>", start)
                    end_tag = text.find("<|end|>", start)

                    if return_tag != -1:
                        answer = text[start:return_tag].strip()
                    elif end_tag != -1:
                        answer = text[start:end_tag].strip()
                    else:
                        answer = text[start:].strip()

                # Fallback if no channels found
                if not reasoning and not answer:
                    # Try to clean up any remaining special tokens
                    clean_text = text
                    for tag in ["<|start|>", "<|end|>", "<|message|>", "<|return|>"]:
                        clean_text = clean_text.replace(tag, "")
                    answer = clean_text.strip()
            else:
                # For baseline: handle different formats
                reasoning = ""
                answer = ""
                clean_text = text

                # Remove common special tokens
                for tag in ["<|start|>", "<|end|>", "<|message|>", "<|return|>"]:
                    clean_text = clean_text.replace(tag, "")

                # Check if it has assistant<|channel|>commentary format
                if "assistant<|channel|>commentary" in clean_text:
                    # Extract commentary (reasoning)
                    commentary_start = clean_text.find("assistant<|channel|>commentary")
                    if commentary_start != -1:
                        commentary_start = clean_text.find(
                            "commentary", commentary_start
                        ) + len("commentary")
                        # Find where assistant starts again (final answer)
                        next_assistant = clean_text.find("assistant", commentary_start)
                        if next_assistant != -1:
                            reasoning = clean_text[
                                commentary_start:next_assistant
                            ].strip()
                            # Get everything after the second assistant as the answer
                            answer = (
                                clean_text[next_assistant:]
                                .replace("assistant", "", 1)
                                .strip()
                            )
                            # Remove any channel tags from answer
                            if "<|channel|>" in answer:
                                answer = answer.split("<|channel|>")[-1].strip()
                        else:
                            reasoning = clean_text[commentary_start:].strip()

                # If no commentary format, try channel tags
                elif (
                    "<|channel|>commentary" in clean_text
                    or "<|channel|>analysis" in clean_text
                ):
                    # Try to extract commentary/analysis channel
                    for channel in ["commentary", "analysis"]:
                        channel_tag = f"<|channel|>{channel}"
                        if channel_tag in clean_text:
                            start = clean_text.find(channel_tag) + len(channel_tag)
                            # Find next channel or end
                            next_channel = clean_text.find("<|channel|>", start)
                            if next_channel != -1:
                                reasoning = clean_text[start:next_channel].strip()
                                answer = clean_text[next_channel:].strip()
                                # Remove channel tags from answer
                                for tag in [
                                    "<|channel|>final",
                                    "<|channel|>commentary",
                                    "<|channel|>analysis",
                                ]:
                                    answer = answer.replace(tag, "")
                            else:
                                reasoning = clean_text[start:].strip()
                            break

                # Fallback: split on double newline
                if not reasoning and not answer:
                    parts = clean_text.split("\n\n", 1)
                    if len(parts) > 1:
                        reasoning = parts[0].strip()
                        answer = parts[1].strip()
                    else:
                        reasoning = ""
                        answer = clean_text.strip()

            return {"reasoning": reasoning, "answer": answer}

        # Build actual prompts for display
        finetuned_prompt = f"reasoning language: {lang}\n\n{prompt}"
        baseline_display_prompt = (
            f"{baseline_prefix} {prompt}".strip() if baseline_prefix else prompt
        )

        return jsonify(
            {
                "finetuned": {
                    **parse_response(finetuned_result, "finetuned"),
                    "prompt": finetuned_prompt,
                },
                "baseline": {
                    **parse_response(baseline_result, "baseline"),
                    "prompt": baseline_display_prompt,
                },
            }
        )
    except Exception as e:
        import traceback

        tb = traceback.format_exc()
        logger.error(f"Error: {e}\n{tb}")
        return jsonify({"error": str(e) or repr(e), "traceback": tb}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
