module Types exposing (..)

import Animation
import Http



-- INPUT DATA


type alias Flags =
    { dois : List String
    , serverURL : String
    , authorName : String
    , authorProfileURL : String
    }



-- MODEL


type alias Paper =
    { doi : DOI
    , title : Maybe String
    , journal : Maybe String
    , authors : Maybe String
    , year : Maybe Int
    , issn : Maybe String
    , isOpenAccess : Maybe Bool
    , oaPathway : Maybe String
    , oaPathwayURI : Maybe String
    , recommendedPathway : Maybe OaPathway
    }


type alias OaPathway =
    -- OaPathway is the union of Policy and PathwayDetails, this can probobably be done more nicely
    { articleVersion : String
    , locations : List String
    , prerequisites : Maybe (List String)
    , conditions : Maybe (List String)
    , notes : Maybe (List String)
    , urls : Maybe (List NamedUrl)
    , policyUrl : String
    }


type alias PathwayDetails =
    { articleVersion : String
    , locations : List String
    , prerequisites : Maybe (List String)
    , conditions : Maybe (List String)
    , notes : Maybe (List String)
    }


type alias Policy =
    { policyUrl : String
    , urls : Maybe (List NamedUrl)
    }



-- GENERAL PURPOSE


type alias DOI =
    String


type alias NamedUrl =
    { description : String
    , url : String
    }



-- BACKEND PAPER


type alias BackendPaper =
    { doi : DOI
    , title : Maybe String
    , journal : Maybe String
    , authors : Maybe String
    , year : Maybe Int
    , issn : Maybe String
    , isOpenAccess : Maybe Bool
    , oaPathway : Maybe String
    , oaPathwayURI : Maybe String
    , pathwayDetails : Maybe (List BackendPolicy)
    }


type alias BackendPolicy =
    { urls : Maybe (List NamedUrl)
    , permittedOA : Maybe (List PermittedOA)
    , policyUrl : Maybe String
    }


type alias PermittedOA =
    { additionalOaFee : String
    , location : BackendLocation
    , articleVersion : List String
    , conditions : Maybe (List String)
    , prerequisites : Maybe BackendPrerequisites
    }


type alias BackendPrerequisites =
    { prerequisites : List String
    , prerequisites_phrases : List BackendPhrase
    }


type alias BackendPhrase =
    { value : String
    , phrase : String
    , language : String
    }


type alias BackendLocation =
    { location : List String
    , namedRepository : Maybe (List String)
    }



-- MSG


type Msg
    = GotPaper (Result Http.Error BackendPaper)
    | Animate Animation.Msg
