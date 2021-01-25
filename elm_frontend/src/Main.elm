module Main exposing (main)

import Animation exposing (percent)
import Array exposing (Array)
import BackendPaper exposing (BackendPaper, paperDecoder)
import Browser
import BuggyPaper exposing (BuggyPaper)
import Debug
import FreePathwayPaper exposing (FreePathwayPaper, NoCostOaPathway, PolicyMetaData, recommendPathway)
import GeneralTypes exposing (DOI, PaperMetadata, renderPaperMetaData, renderUrl)
import Html exposing (Html, a, button, div, footer, h2, main_, p, section, small, span, text)
import Html.Attributes exposing (class, href, target, title)
import Html.Events exposing (onClick)
import HtmlUtils exposing (ulWithHeading)
import Http
import HttpBuilder exposing (withHeader)
import OpenAccessPaper as OpenAccessPaper exposing (OpenAccessPaper)
import OtherPathwayPaper exposing (OtherPathwayPaper)


type alias Model =
    { initialDOIs : List DOI
    , freePathwayPapers : Array FreePathwayPaper
    , otherPathwayPapers : List OtherPathwayPaper
    , openAccessPapers : List OpenAccessPaper
    , buggyPapers : List BuggyPaper
    , numFailedDOIRequests : Int
    , authorName : String
    , authorProfileURL : String
    , serverURL : String
    , style : Animation.State
    }



-- INIT


type alias Flags =
    { dois : List String
    , serverURL : String
    , authorName : String
    , authorProfileURL : String
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { initialDOIs = flags.dois
      , freePathwayPapers = Array.empty
      , otherPathwayPapers = []
      , openAccessPapers = []
      , buggyPapers = []
      , numFailedDOIRequests = 0
      , authorName = flags.authorName
      , authorProfileURL = flags.authorProfileURL
      , serverURL = flags.serverURL
      , style = Animation.style [ Animation.width (percent 0), Animation.opacity 1 ]
      }
    , Cmd.batch (List.map (fetchPaper flags.serverURL) flags.dois)
    )


fetchPaper : String -> String -> Cmd Msg
fetchPaper serverURL doi =
    HttpBuilder.get (serverURL ++ "/api/papers?doi=" ++ doi)
        |> withHeader "Content-Type" "application/json"
        |> HttpBuilder.withExpect (Http.expectJson GotPaper paperDecoder)
        |> HttpBuilder.request



-- VIEW


view : Model -> Html Msg
view model =
    let
        paperMetaCompare : { a | meta : PaperMetadata } -> { a | meta : PaperMetadata } -> Order
        paperMetaCompare p1 p2 =
            let
                y1 =
                    Maybe.withDefault 9999999999 p1.meta.year

                y2 =
                    Maybe.withDefault 9999999999 p2.meta.year
            in
            compare y2 y1

        indexedPapersYearComp : ( Int, { a | meta : PaperMetadata } ) -> ( Int, { a | meta : PaperMetadata } ) -> Order
        indexedPapersYearComp ( _, p1 ) ( _, p2 ) =
            paperMetaCompare p1 p2

        paywalledNoCostPathwayPapers =
            List.sortWith indexedPapersYearComp (Array.toIndexedList model.freePathwayPapers)

        nonFreePolicyPapers =
            List.sortWith paperMetaCompare model.otherPathwayPapers
    in
    div []
        [ span
            [ class "container"
            , class "progressbar__container"
            ]
            [ span (Animation.render model.style ++ [ class "progressbar_progress" ]) [ text "" ] ]
        , main_ []
            [ renderPaywalledNoCostPathwayPapers paywalledNoCostPathwayPapers
            , renderNonFreePolicyPapers nonFreePolicyPapers
            , OpenAccessPaper.viewList model.openAccessPapers
            , renderBuggyPapers model.buggyPapers
            ]
        , renderFooter model.authorProfileURL
        ]



-- UPDATE


type Msg
    = GotPaper (Result Http.Error BackendPaper)
    | TogglePathwayDisplay Int
    | Animate Animation.Msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        updateStyle m =
            { m
                | style =
                    Animation.interrupt
                        [ Animation.to
                            [ Animation.width (percent (percentDOIsFetched model))
                            , Animation.opacity
                                (toFloat
                                    (min 1 (List.length model.initialDOIs - numberFetchedPapers m))
                                )
                            ]
                        ]
                        model.style
            }

        togglePathwayVisibility : Array FreePathwayPaper -> Int -> Array FreePathwayPaper
        togglePathwayVisibility papers id =
            papers
                |> Array.get id
                |> Maybe.map (\p -> { p | pathwayVisible = not p.pathwayVisible })
                |> Maybe.map (\p -> Array.set id p papers)
                |> Maybe.withDefault papers
    in
    case msg of
        GotPaper (Ok backendPaper) ->
            ( model
                |> classifyPaper backendPaper
                |> updateStyle
            , Cmd.none
            )

        GotPaper (Err error) ->
            let
                _ =
                    Debug.log "Error in GotPaper" error
            in
            ( { model | numFailedDOIRequests = model.numFailedDOIRequests + 1 }
            , Cmd.none
            )

        TogglePathwayDisplay paperId ->
            ( { model | freePathwayPapers = togglePathwayVisibility model.freePathwayPapers paperId }
            , Cmd.none
            )

        Animate animMsg ->
            ( { model
                | style = Animation.update animMsg model.style
              }
            , Cmd.none
            )


classifyPaper : BackendPaper -> Model -> Model
classifyPaper backendPaper model =
    let
        isOpenAccess =
            backendPaper.isOpenAccess

        pathwayUri =
            backendPaper.oaPathwayURI

        meta =
            { doi = backendPaper.doi
            , title = backendPaper.title
            , journal = backendPaper.journal
            , authors = backendPaper.authors
            , year = backendPaper.year
            , issn = backendPaper.issn
            }

        recommendedPathway =
            Maybe.andThen recommendPathway backendPaper.pathwayDetails
    in
    case ( isOpenAccess, pathwayUri, recommendedPathway ) of
        ( Just False, Just pwUri, Just pathway ) ->
            FreePathwayPaper meta pwUri pathway False
                |> (\p -> { model | freePathwayPapers = Array.push p model.freePathwayPapers })

        ( Just False, Just pwUri, Nothing ) ->
            OtherPathwayPaper meta pwUri
                |> (\p -> { model | otherPathwayPapers = model.otherPathwayPapers ++ [ p ] })

        ( Just True, _, _ ) ->
            OpenAccessPaper meta.doi
                meta.title
                meta.journal
                meta.authors
                meta.year
                meta.issn
                |> (\p -> { model | openAccessPapers = model.openAccessPapers ++ [ p ] })

        _ ->
            { model | buggyPapers = model.buggyPapers ++ [ BuggyPaper backendPaper.doi backendPaper.journal backendPaper.oaPathway ] }



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Animation.subscription Animate [ model.style ]



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- ------------------------------
-- TO BE EXTRACTED
-- ------------------------------
-- LOADING BAR


numberFetchedPapers : Model -> Int
numberFetchedPapers model =
    List.length model.buggyPapers
        + Array.length model.freePathwayPapers
        + List.length model.openAccessPapers
        + List.length model.otherPathwayPapers
        + model.numFailedDOIRequests


percentDOIsFetched : Model -> Float
percentDOIsFetched model =
    -- Report at least 10 percent at all times to provide immediate loading feedback.
    max
        10
        (100
            * (model |> numberFetchedPapers |> toFloat)
            / (model.initialDOIs |> List.length |> toFloat)
        )



-- PAPER


renderFreePathwayPaper : ( Int, FreePathwayPaper ) -> Html Msg
renderFreePathwayPaper ( id, { pathwayVisible, recommendedPathway } as paper ) =
    let
        pathwayClass =
            if pathwayVisible then
                ""

            else
                "d-none"
    in
    div [ class "row mb-3 author-pubs mb-4 pt-3 border-top" ]
        [ div [ class "paper-details col-12 fs-6 mb-2 mb-md-0 col-md-9" ]
            [ div []
                (renderPaperMetaData paper.meta)
            , div [ class pathwayClass ]
                (renderRecommendedPathway paper.oaPathwayURI recommendedPathway)
            ]
        , div [ class "col-12 col-md-3 fs-6 text-md-end" ]
            (renderPathwayButtons pathwayVisible ( id, paper.meta ))
        ]


renderNonFreePathwayPaper : OtherPathwayPaper -> Html Msg
renderNonFreePathwayPaper paper =
    div [ class "row mb-3 author-pubs mb-4 pt-3 border-top" ]
        [ div
            [ class "paper-details col-12 fs-6 mb-2 mb-md-0 col-md-9" ]
            (renderPaperMetaData paper.meta)
        ]


renderPathwayButtons : Bool -> ( Int, { a | title : Maybe String } ) -> List (Html Msg)
renderPathwayButtons pathwayIsVisible ( id, { title } ) =
    let
        paperTitle =
            Maybe.withDefault "Unknown title" title

        verb =
            if pathwayIsVisible then
                "Hide"

            else
                "Show"

        style =
            if pathwayIsVisible then
                "btn btn-light"

            else
                "btn btn-success"
    in
    [ div []
        [ button
            [ onClick (TogglePathwayDisplay id)
            , class style
            , Html.Attributes.title (verb ++ "Open Access pathway for: " ++ paperTitle)
            ]
            [ text (verb ++ " Open Access pathway")
            ]
        ]
    ]


renderRecommendedPathway : String -> ( PolicyMetaData, NoCostOaPathway ) -> List (Html Msg)
renderRecommendedPathway journalPolicyUrl ( policy, { locationLabelsSorted, articleVersions, prerequisites, conditions, embargo, notes } ) =
    let
        addEmbargo : Maybe String -> Maybe (List String) -> Maybe (List String)
        addEmbargo emb prereqs =
            case ( emb, prereqs ) of
                ( Just e, Just p ) ->
                    Just (List.append [ "If " ++ e ++ " have passed since publication" ] p)

                ( Just e, Nothing ) ->
                    Just [ "If " ++ e ++ " have passed since publication" ]

                ( Nothing, Just p ) ->
                    Just p

                _ ->
                    Nothing

        articleVersion =
            articleVersions
                |> List.filter (\v -> v == "published")
                |> List.head
                |> Maybe.withDefault (String.join " or " articleVersions)
    in
    List.concat
        [ [ p [] [ text "The publisher has a policy that lets you:" ] ]
        , locationLabelsSorted
            |> List.take 1
            |> ulWithHeading ("upload the " ++ articleVersion ++ " version to any of the following:") text
        , [ p [] [ text " You don't have pay a fee to do this." ] ]
        , prerequisites
            |> addEmbargo embargo
            |> Maybe.map (ulWithHeading "But only:" text)
            |> Maybe.withDefault [ text "" ]
        , conditions
            |> Maybe.map (ulWithHeading "Conditions are:" text)
            |> Maybe.withDefault [ text "" ]
        , notes
            |> Maybe.map (ulWithHeading "Notes regarding this pathway:" text)
            |> Maybe.withDefault [ text "" ]
        , policy.additionalUrls
            |> Maybe.map (ulWithHeading "The publisher has provided the following links to further information:" renderUrl)
            |> Maybe.withDefault [ text "" ]
        , [ p []
                [ policy.notes
                    |> Maybe.map (String.append "Regarding the policy they note: ")
                    |> Maybe.withDefault ""
                    |> text
                ]
          ]
        , [ p []
                [ text "More information about this and other Open Access policies for this publication can be found in the "
                , a [ href journalPolicyUrl, class "link", class "link-secondary" ] [ text "Sherpa Policy Database" ]
                ]
          ]
        ]



-- PAPER SECTIONS


renderPaywalledNoCostPathwayPapers : List ( Int, FreePathwayPaper ) -> Html Msg
renderPaywalledNoCostPathwayPapers papers =
    section [ class "mb-5" ]
        [ h2 []
            [ text "Unnecessarily paywalled publications"
            ]
        , p [ class "fs-6 mb-4" ]
            [ text
                ("We found no Open Access version for the following publications. "
                    ++ "However, the publishers likely allow no-cost re-publication as Open Access."
                )
            ]
        , div [] (List.map renderFreePathwayPaper papers)
        ]


renderNonFreePolicyPapers : List OtherPathwayPaper -> Html Msg
renderNonFreePolicyPapers papers =
    if List.isEmpty papers then
        text ""

    else
        section [ class "mb-5" ]
            [ h2 []
                [ text "Publications with non-free publisher policies"
                ]
            , p [ class "fs-6 mb-4" ]
                [ text
                    ("The following publications do not seem to have any no-cost Open Access "
                        ++ "re-publishing pathways, or do not allow Open Access publishing at all."
                    )
                ]
            , div [] (List.map renderNonFreePathwayPaper papers)
            ]


renderBuggyPapers : List BuggyPaper -> Html Msg
renderBuggyPapers papers =
    if List.isEmpty papers then
        text ""

    else
        section [ class "mb-5" ]
            [ h2 []
                [ text "Publications we had issues with"
                ]
            , div [ class "container" ]
                (List.map
                    (\p ->
                        div []
                            [ a [ href ("https://doi.org/" ++ p.doi), target "_blank", class "link-secondary" ]
                                [ text p.doi
                                ]
                            , case p.oaPathway of
                                Just _ ->
                                    text (" (unknown publisher policy for: " ++ Maybe.withDefault "Unknown Journal" p.journal ++ ")")

                                _ ->
                                    text ""
                            ]
                    )
                    papers
                )
            ]



-- SOURCE PROFILE


renderFooter : String -> Html Msg
renderFooter authorProfileURL =
    footer [ class "container text-center m-4" ]
        [ small []
            [ text "("
            , a [ href authorProfileURL, target "_blank", class "link-dark" ]
                [ text "Source Profile"
                ]
            , text " that was used to retreive the author's papers.)"
            ]
        ]
