from copy import deepcopy
from typing import Optional

from wbf.schemas import OAPathway, PaperWithOAStatus, PaperWithOAPathway
from wbf.sherpa import get_pathway as sherpa_pathway_api

# TODO: Consider for service version that nocost is currently assigned to pathways with
# additional prerequisites (e.g. specific funders or funders mandating OA)
# TODO: For service version, check if embargo still preventing OA and don't recommend
# embargoed papers for re-publication


def oa_pathway(
    paper: PaperWithOAStatus, cache=None, api_key: Optional[str] = None
) -> PaperWithOAPathway:
    """Enrich a given paper with information about the available open access pathway
    collected from the Sherpa API.

    Cache can be anything that exposes ``get(key, default)`` and ``__setitem__``
    """
    details = None
    if paper.is_open_access:
        pathway = OAPathway.already_oa
    elif paper.is_open_access is None:
        pathway = OAPathway.not_attempted
    else:
        if cache is not None:
            pathway = cache.get(paper.issn, None)
            if not pathway:
                pathway, details = sherpa_pathway_api(paper.issn, api_key)
                cache[paper.issn] = pathway
        else:
            pathway, details = sherpa_pathway_api(paper.issn, api_key)

    return PaperWithOAPathway(
        oa_pathway=pathway, oa_pathway_details=details, **paper.dict()
    )


def remove_costly_oa_from_publisher_policy(policy: dict) -> dict:
    """A potential input is ``FullPaper.oa_pathway_details[i]``"""
    _policy = deepcopy(policy)

    _policy["permitted_oa"] = [
        poa for poa in _policy["permitted_oa"] if poa["additional_oa_fee"] == "no"
    ]

    return _policy
