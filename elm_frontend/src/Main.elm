module Main exposing (..)

import Animation exposing (percent)
import Api exposing (..)
import Array exposing (..)
import Browser
import Browser.Navigation exposing (back)
import Html exposing (..)
import Html.Attributes exposing (class)
import Html.Events exposing (..)
import Types exposing (..)
import Utils exposing (..)
import Views exposing (..)



-- MODEL


type alias Model =
    { unfetchedDOIs : List DOI
    , fetchedPapers : List Paper
    , freePathwayPapers : Array Paper
    , otherPathwayPapers : List Paper
    , openAccessPapers : List Paper
    , buggyPapers : List Paper
    , authorName : String
    , authorProfileURL : String
    , serverURL : String
    , style : Animation.State
    }



-- SETUP


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { unfetchedDOIs = Maybe.withDefault [] (List.tail flags.dois)
      , fetchedPapers = []
      , freePathwayPapers = Array.empty
      , otherPathwayPapers = []
      , openAccessPapers = []
      , buggyPapers = []
      , authorName = flags.authorName
      , authorProfileURL = flags.authorProfileURL
      , serverURL = flags.serverURL
      , style = Animation.style [ Animation.width (percent 0), Animation.opacity 1 ]
      }
    , case List.head flags.dois of
        Just nextDOI ->
            fetchPaper flags.serverURL nextDOI

        Nothing ->
            Cmd.none
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Animation.subscription Animate [ model.style ]



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotPaper (Ok backendPaper) ->
            let
                classifiedPaper =
                    backendPaper |> toPaper |> classifyPaper

                updatedModel =
                    { model
                        | style =
                            Animation.interrupt
                                [ Animation.to
                                    [ Animation.width (percent (percentDOIsFetched model))
                                    , Animation.opacity (toFloat (min 1 (List.length model.unfetchedDOIs)))
                                    ]
                                ]
                                model.style
                    }
            in
            ( case classifiedPaper of
                FreePathway paper ->
                    { updatedModel
                        | freePathwayPapers = Array.push paper model.freePathwayPapers
                        , unfetchedDOIs = List.drop 1 model.unfetchedDOIs
                    }

                OtherPathway paper ->
                    { updatedModel
                        | otherPathwayPapers = List.append model.otherPathwayPapers [ paper ]
                        , unfetchedDOIs = List.drop 1 model.unfetchedDOIs
                    }

                OpenAccess paper ->
                    { updatedModel
                        | openAccessPapers = List.append model.openAccessPapers [ paper ]
                        , unfetchedDOIs = List.drop 1 model.unfetchedDOIs
                    }

                Buggy paper ->
                    { updatedModel
                        | buggyPapers = List.append model.buggyPapers [ paper ]
                        , unfetchedDOIs = List.drop 1 model.unfetchedDOIs
                    }
            , case List.head model.unfetchedDOIs of
                Just nextDOI ->
                    fetchPaper model.serverURL nextDOI

                Nothing ->
                    Cmd.none
            )

        -- TODO: add the erroneous dois as well?
        GotPaper (Err _) ->
            ( { model | unfetchedDOIs = List.drop 1 model.unfetchedDOIs }
            , Cmd.none
            )

        TogglePathwayDisplay ->
            ( model, Cmd.none )

        Animate animMsg ->
            ( { model
                | style = Animation.update animMsg model.style
              }
            , Cmd.none
            )



-- VIEW


view : Model -> Html Msg
view model =
    let
        indexedPapersYearComp : ( Int, Paper ) -> ( Int, Paper ) -> Order
        indexedPapersYearComp ( _, p1 ) ( _, p2 ) =
            optionalYearComparison p1 p2

        paywalledNoCostPathwayPapers =
            List.sortWith indexedPapersYearComp (Array.toIndexedList model.freePathwayPapers)

        nonFreePolicyPapers =
            List.sortWith optionalYearComparison model.otherPathwayPapers

        openAccessPapers =
            List.sortWith optionalYearComparison model.openAccessPapers

        buggyPapers =
            List.sortWith optionalYearComparison model.buggyPapers
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
            , renderOpenAccessPapers openAccessPapers
            , renderBuggyPapers buggyPapers
            ]
        , renderFooter model.authorProfileURL
        ]



-- LOADING BAR


percentDOIsFetched : Model -> Float
percentDOIsFetched model =
    max
        10
        (100
            * toFloat (List.length model.fetchedPapers)
            / (toFloat (List.length model.fetchedPapers) + toFloat (List.length model.unfetchedDOIs))
        )



-- BACKEND-PAPER >>> PAPER


classifyPaper : Paper -> ClassifiedPaper
classifyPaper paper =
    let
        isOpenAccess =
            paper.isOpenAccess

        oaPathway =
            paper.oaPathway
    in
    case ( isOpenAccess, oaPathway ) of
        ( Just False, Just "nocost" ) ->
            FreePathway paper

        ( Just False, Just "other" ) ->
            OtherPathway paper

        ( Just True, _ ) ->
            OpenAccess paper

        _ ->
            Buggy paper


toPaper : BackendPaper -> Paper
toPaper backendPaper =
    { doi = backendPaper.doi
    , title = backendPaper.title
    , journal = backendPaper.journal
    , authors = backendPaper.authors
    , year = backendPaper.year
    , issn = backendPaper.issn
    , isOpenAccess = backendPaper.isOpenAccess
    , oaPathway = backendPaper.oaPathway
    , oaPathwayURI = backendPaper.oaPathwayURI
    , recommendedPathway = Maybe.andThen parsePolicies backendPaper.pathwayDetails
    }


parsePolicies : List BackendPolicy -> Maybe ( PolicyMetaData, NoCostOaPathway )
parsePolicies policies =
    policies
        |> flattenPolicies
        |> List.map noCostOaPathway
        |> List.filterMap identity
        |> List.sortWith orderByPathwayQuality
        |> List.head


flattenPolicies : List BackendPolicy -> List ( PolicyMetaData, Pathway )
flattenPolicies policies =
    policies
        |> List.map extractPathways
        |> List.concatMap (\( meta, pathways ) -> pathways |> List.map (Tuple.pair meta))


extractPathways : BackendPolicy -> ( PolicyMetaData, List Pathway )
extractPathways backendPolicy =
    ( backendPolicy
        |> parsePolicyMetaData
    , backendPolicy.permittedOA
        |> Maybe.withDefault []
        |> List.map parsePathway
    )


parsePathway : BackendPermittedOA -> Pathway
parsePathway { articleVersions, location, prerequisites, conditions, additionalOaFee, embargo } =
    let
        embargoToString : BackendEmbargo -> String
        embargoToString { amount, units } =
            String.join " " [ String.fromInt amount, units ]
    in
    { articleVersions =
        case articleVersions of
            [] ->
                Nothing

            _ ->
                Just articleVersions
    , locations = location |> parseLocations
    , prerequisites = prerequisites |> Maybe.map parsePrequisites
    , conditions = conditions
    , additionalOaFee = additionalOaFee
    , embargo = embargo |> Maybe.map embargoToString
    }


orderByPathwayQuality : ( PolicyMetaData, NoCostOaPathway ) -> ( PolicyMetaData, NoCostOaPathway ) -> Order
orderByPathwayQuality p1 p2 =
    EQ


noCostOaPathway : ( PolicyMetaData, Pathway ) -> Maybe ( PolicyMetaData, NoCostOaPathway )
noCostOaPathway ( metadata, pathway ) =
    case ( pathway.additionalOaFee, pathway.locations, pathway.articleVersions ) of
        ( "no", Just locations, Just articleVersions ) ->
            Just
                ( metadata
                , { articleVersions = articleVersions
                  , locations = locations
                  , prerequisites = pathway.prerequisites
                  , conditions = pathway.conditions
                  , embargo = pathway.embargo
                  }
                )

        _ ->
            Nothing


parsePolicyMetaData : BackendPolicy -> PolicyMetaData
parsePolicyMetaData { policyUrl, urls, notes } =
    { profileUrl = policyUrl
    , additionalUrls = urls
    , notes = notes
    }


parsePrequisites : BackendPrerequisites -> List String
parsePrequisites { prerequisites_phrases } =
    prerequisites_phrases
        |> List.map (\item -> item.phrase)


parseLocations : BackendLocation -> Maybe (List String)
parseLocations { location, namedRepository } =
    let
        locations =
            List.concat [ location, Maybe.withDefault [] namedRepository ]
                |> List.filter (\loc -> loc /= "named_repository")
                |> List.map
                    (\loc ->
                        case loc of
                            "academic_social_network" ->
                                "Academic Social Networks"

                            "non_commercial_repository" ->
                                "Non-commercial Repositories"

                            "authors_homepage" ->
                                "Author's Homepage"

                            a ->
                                String.replace "_" " " a
                    )
    in
    case locations of
        [] ->
            Nothing

        _ ->
            Just locations
