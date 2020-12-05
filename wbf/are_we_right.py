import os
import json
import argparse
from contextlib import contextmanager
from functools import partial
from typing import List

from wbf.oa_pathway import oa_pathway
from wbf.schemas import (
    OAPathway,
    OAStatus,
    PaperWithOAPathway,
    PaperWithOAStatus,
)


@contextmanager
def json_filesystem_cache(name):
    pathway_cache = dict()
    if os.path.isfile(args.pathway_cache):
        with open(args.pathway_cache, "r") as fh:
            pathway_cache = json.load(fh)
            print(f"Loaded {len(pathway_cache)} cached ISSN to OA pathway mappings")
    try:
        yield pathway_cache
    finally:
        print(f"Cached {len(pathway_cache)} ISSN to OA pathway mappings")
        with open(args.pathway_cache, "w") as fh:
            json.dump(pathway_cache, fh, indent=2)


def calculate_metrics(papers: List[PaperWithOAPathway]):
    n_oa = 0
    n_pathway_nocost = 0
    n_pathway_other = 0
    n_unknown = 0

    for p in papers:
        if p.oa_status is OAStatus.oa:
            n_oa += 1
        elif p.oa_pathway is OAPathway.nocost:
            n_pathway_nocost += 1
        elif p.oa_pathway is OAPathway.other:
            n_pathway_other += 1
        elif p.oa_status is OAStatus.not_found or p.oa_pathway is OAPathway.not_found:
            n_unknown += 1

    return n_oa, n_pathway_nocost, n_pathway_other, n_unknown


if __name__ == "__main__":
    # TODO: Consider checking against publicly available publishers / ISSNS (e.g. elife)
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Limit the number of papers to process, set to 0 to remove limit.",
    )
    parser.add_argument(
        "--pathway-cache",
        type=str,
        default="./pathway.json",
        help="Path to cache open access pathway information at.",
    )
    parser.add_argument(
        "--unpaywall-extract",
        type=str,
        default="../tests/assets/unpaywall_subset.jsonl",
        help="Path to extract of unpaywall dataset with doi, issn and oa status",
    )
    args = parser.parse_args()

    # Load data
    dataset_file_path = os.path.join(os.path.dirname(__file__), args.unpaywall_extract)
    with open(dataset_file_path, "r") as fh:
        input_of_papers = [json.loads(line) for line in fh]

    if args.limit:
        input_of_papers = input_of_papers[: args.limit]

    # TODO: Skip papers with ISSNs for which cache says no policy could be found
    papers_with_oa_status = [
        PaperWithOAStatus(
            doi=paper["doi"],
            issn=paper["journal_issn_l"],
            oa_status=("oa" if paper["is_oa"] else "not_oa"),
        )
        for paper in input_of_papers
        if paper["journal_issn_l"] is not None
    ]

    with json_filesystem_cache(args.pathway_cache) as pathway_cache:
        # Enrich data
        papers_with_pathway = map(
            partial(oa_pathway, cache=pathway_cache), papers_with_oa_status
        )

        # Calculate & report metrics
        n_pubs = len(input_of_papers)
        n_oa, n_pathway_nocost, n_pathway_other, n_unknown = calculate_metrics(
            papers_with_pathway
        )

    print(f"looked at {n_pubs} publications")
    print(f"{n_oa} are already OA")
    print(f"{n_pathway_nocost} could be OA at no cost")
    print(f"{n_pathway_other} has other OA pathway(s)")
    print(f"{n_unknown} could not be determined")
