import pytest
from fastapi.testclient import TestClient

from wbf.schemas import OAPathway, PaperWithOAPathway, FullPaper
from wbf import main
from wbf.deps import Settings, get_settings
from wbf.semantic_scholar import Author


def get_settings_override():
    return Settings(sherpa_api_key="DUMMY-API-KEY", unpaywall_email="TEST@MAIL.LOCAL")


main.app.dependency_overrides[get_settings] = get_settings_override


def test_get_landing_page(client: TestClient) -> None:
    r = client.get("/")
    assert r.ok


@pytest.mark.parametrize(
    "profile,provider",
    [
        (51453144, "semantic_scholar.get_author_with_papers"),
        ("0000-0000-0000-0000", "orcid.get_author_with_papers"),
        ("firstname lastname", "crossref.get_author_with_papers"),
    ],
)
def test_get_publications_for_author(
    profile, provider, monkeypatch, client: TestClient
) -> None:
    url = f"/authors?profile={profile}"

    monkeypatch.setattr(
        f"wbf.api.{provider}",
        lambda *a, **kw: Author(
            name="Dummy Author", papers=[FullPaper(doi="10.1007/s00580-005-0536-0")]
        ),
    )

    monkeypatch.setattr(
        "wbf.api._construct_paper",
        lambda *a, **kw: FullPaper(
            issn="1618-5641",
            doi="10.1007/s00580-005-0536-0",
            oa_status=False,
            oa_pathway=OAPathway.nocost.value,
            oa_pathway_details=[],
            title="Best Paper Ever!",
        ),
    )

    r = client.get(url)
    assert r.ok

    r = client.get(url, headers={"accept": "text/html"})
    assert r.ok

    r = client.get(url, headers={"accept": "application/json"})
    assert r.ok

    r = client.get(url, headers={"accept": "unspported/type"})
    assert not r.ok
    assert r.status_code == 406

    r = client.get("/authors")
    assert not r.ok
    assert r.status_code == 422


@pytest.mark.parametrize(
    "profile,provider",
    [
        (51453144, "semantic_scholar.get_author_with_papers"),
        ("0000-0000-0000-0000", "orcid.get_author_with_papers"),
        ("firstname lastname", "crossref.get_author_with_papers"),
    ],
)
def test_no_author(profile, provider, monkeypatch, client: TestClient) -> None:
    url = f"/authors?profile={profile}"

    monkeypatch.setattr(f"wbf.api.{provider}", lambda *a, **kw: None)

    r = client.get(url)
    assert not r.ok
    assert r.status_code == 404


@pytest.mark.parametrize(
    "profile,provider",
    [
        (51453144, "semantic_scholar.get_author_with_papers"),
        ("0000-0000-0000-0000", "orcid.get_author_with_papers"),
        ("firstname lastname", "crossref.get_author_with_papers"),
    ],
)
def test_no_publications_for_author(
    profile, provider, monkeypatch, client: TestClient
) -> None:
    url = f"/authors?profile={profile}"

    monkeypatch.setattr(
        f"wbf.api.{provider}", lambda *a, **kw: Author(name="Dummy Author", papers=[])
    )

    r = client.get(url)
    assert r.ok


def test_get_paper_missing_args(client: TestClient) -> None:
    r = client.get("/papers")
    assert not r.ok
    assert r.status_code == 422


def test_get_paper(monkeypatch, client: TestClient) -> None:
    issn = "1618-5641"
    doi = "10.1007/s00580-005-0536-8"
    is_open_access = False
    oa_pathway = OAPathway.nocost.value

    monkeypatch.setattr(
        "wbf.api.unpaywall_get_paper",
        lambda *a, **kw: FullPaper(doi=doi, issn=issn, is_open_access=is_open_access),
    )
    monkeypatch.setattr(
        "wbf.api.oa_pathway",
        lambda paper, **kw: PaperWithOAPathway(oa_pathway=oa_pathway, **paper.dict()),
    )

    r = client.get(f"/papers?doi={doi}")
    assert r.ok
    paper = r.json()
    assert paper["is_open_access"] == is_open_access
    assert paper["oa_pathway"] == oa_pathway
    assert paper["doi"] == doi
    assert paper["issn"] == issn


def test_media_type_dependent_error_pages(monkeypatch, client: TestClient) -> None:
    monkeypatch.setattr("wbf.api._construct_paper", lambda *a, **kw: None)

    unknown_doi = "doesnt/exist"

    r = client.get(f"/papers?doi={unknown_doi}", headers={"accept": "text/html"})
    assert r.status_code == 404
    assert unknown_doi in r.content.decode()

    r = client.get(f"/papers?doi={unknown_doi}", headers={"accept": "application/json"})
    assert r.status_code == 404
    assert "detail" in r.json()
