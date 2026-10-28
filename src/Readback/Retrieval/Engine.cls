/// The only class, with Readback.Retrieval.Operation, that calls the platform's RAG classes (experimental in
/// build 154, docs/probes.md Probe 8). It owns the local embedding provider, the two vector stores, the two
/// knowledge bases and the tool manager that runs the searches.
///
/// Retrieval never downloads anything at run time: the embedding model must already be in the cache directory
/// (the image build puts it there, Probe 10). When it is not, or anything else fails, Available is false with a
/// reason, and the caller treats that as a failure, never as "nothing found".
Class Readback.Retrieval.Engine Extends %RegisteredObject
{

Parameter PolicyTable = "Readback_Retrieval.PolicyVec";

Parameter CaseTable = "Readback_Retrieval.CaseVec";

Parameter ModelName = "AllMiniLML6V2";

Parameter Dimensions = 384;

/// A result below this score is dropped.
Parameter MinScore = 0.3;

Property Available As %Boolean [ InitialExpression = 0 ];

Property Reason As %String(MAXLEN = 500);

Property IndexVersion As %String(MAXLEN = 100);

Property Embedding As %RegisteredObject;

Property PolicyStore As %RegisteredObject;

Property CaseStore As %RegisteredObject;

Property PolicyKB As %RegisteredObject;

Property CaseKB As %RegisteredObject;

Property Tools As %RegisteredObject;

/// Builds everything. pCacheDir defaults to FASTEMBED_CACHE_DIR. Never raises: a failure leaves Available false.
Method Build(pCacheDir As %String = "", pPolicyFile As %String = "") As %Status
{
	Set ..Available = 0
	Set tDir = $Select(pCacheDir'="":pCacheDir, 1:$System.Util.GetEnviron("FASTEMBED_CACHE_DIR"))
	If tDir = "" { Set ..Reason = "the embedding model cache directory is not set" Quit $$$OK }
	If '..HasModel(tDir) {
		Set ..Reason = "the embedding model is not in the cache directory; retrieval does not download it at run time"
		Quit $$$OK
	}
	Try {
		Set ..Embedding = ##class(%AI.RAG.Embedding.FastEmbed).Create()
		Set ..PolicyStore = ..NewStore(..#PolicyTable)
		Set ..CaseStore = ..NewStore(..#CaseTable)
		Set ..PolicyKB = ##class(%AI.RAG.KnowledgeBase).%New("policy", "Laboratory policy passages")
		Set tSC = ..PolicyKB.Build(..Embedding, ..PolicyStore)
		If $System.Status.IsOK(tSC) {
			Set ..CaseKB = ##class(%AI.RAG.KnowledgeBase).%New("cases", "Human-confirmed cases")
			Set tSC = ..CaseKB.Build(..Embedding, ..CaseStore)
		}
		If $System.Status.IsOK(tSC) {
			Set ..Tools = ##class(%AI.ToolMgr).%New()
			Set tSC = ..PolicyKB.AddToManager(..Tools)
		}
		If $System.Status.IsOK(tSC) { Set tSC = ..CaseKB.AddToManager(..Tools) }
		If $System.Status.IsOK(tSC) {
			Set tSC = ##class(Readback.Retrieval.Policy).EnsureIndexed($This, $Select(pPolicyFile'="":pPolicyFile, 1:##class(Readback.Retrieval.Policy).#File), .tVersion)
		}
		If $System.Status.IsError(tSC) {
			Set ..Reason = ..Redact($System.Status.GetErrorText(tSC))
		} Else {
			Set ..IndexVersion = tVersion, ..Available = 1, ..Reason = ""
		}
	} Catch ex {
		Set ..Reason = ..Redact(ex.DisplayString())
		Set ..Available = 0
	}
	Quit $$$OK
}

ClassMethod Redact(pText As %String) As %String
{
	Quit $Extract(##class(Readback.Config.Mode).Redact(pText), 1, 500)
}

Method NewStore(pTable As %String) As %RegisteredObject
{
	Set tStore = ##class(%AI.RAG.VectorStore.IRIS).%New()
	Set tStore.Schema = $Piece(pTable, ".", 1), tStore.TableName = pTable, tStore.Dimensions = ..#Dimensions, tStore.ModelName = ..#ModelName
	Set tSC = tStore.Build()
	If $System.Status.IsError(tSC) { Throw ##class(%Exception.StatusException).CreateFromStatus(tSC) }
	Quit tStore
}

/// True when the cache directory holds the model file.
ClassMethod HasModel(pDir As %String) As %Boolean
{
	Quit:'##class(%File).DirectoryExists(pDir) 0
	Set tFound = 0, tQueue(1) = pDir, tHead = 1, tTail = 1
	While (tHead <= tTail) && 'tFound {
		Set tRS = ##class(%ResultSet).%New("%File:FileSet")
		Do tRS.Execute(tQueue(tHead), "*", "Name", 1)
		While tRS.Next() {
			If tRS.Get("Type") = "D" { Set tTail = tTail + 1, tQueue(tTail) = tRS.Get("Name") }
			ElseIf $Piece(tRS.Get("Name"), "/", *) = "model.onnx" { Set tFound = 1 }
		}
		Set tHead = tHead + 1
	}
	Quit tFound
}

Method PolicyRows() As %Integer
{
	Quit ..CountRows(..#PolicyTable)
}

ClassMethod CountRows(pTable As %String) As %Integer
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_pTable)
	Quit:tRS.%SQLCODE<0 -1
	Do tRS.%Next()
	Quit +tRS.%GetData(1)
}

Method ClearPolicy() As %Status
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM "_..#PolicyTable)
	Quit:tRS.%SQLCODE<0 $System.Status.Error(5001, "Could not empty the policy table: "_tRS.%Message)
	Quit $$$OK
}

Method AddPassage(pPassage As %DynamicObject) As %Status
{
	Quit ..PolicyKB.AddDocument(pPassage.text, {"source":(pPassage.id),"passage":(pPassage.id),"document":(pPassage.source),"title":(pPassage.title)})
}

Method AddCase(pTraceId As %Integer, pText As %String) As %Status
{
	Quit ..CaseKB.AddDocument(pText, {"source":("case-"_pTraceId),"traceId":(pTraceId)})
}

Method RemoveCase(pTraceId As %Integer) As %Status
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM "_..#CaseTable_" WHERE source = ?", "case-"_pTraceId)
	Quit:tRS.%SQLCODE<0 $System.Status.Error(5001, "Could not remove a case: "_tRS.%Message)
	Quit $$$OK
}

/// The answer to a request. Never raises. Available false when retrieval itself failed (then Reason says why).
Method Search(pRequest As Readback.Msg.RetrievalRequest) As Readback.Msg.RetrievalResponse
{
	Set tResp = ##class(Readback.Msg.RetrievalResponse).%New()
	If '..Available {
		Set tResp.Available = 0, tResp.Reason = ..Reason
		Quit tResp
	}
	Try {
		Set tSC = ##class(Readback.Retrieval.Cases).Sync($This)
		If $System.Status.IsError(tSC) { Throw ##class(%Exception.StatusException).CreateFromStatus(tSC) }
		Set tResp.IndexVersion = ..IndexVersion
		Do ..Collect("policy", pRequest.Query, pRequest.MaxPassages, tResp.Passages, 0)
		Do ..Collect("cases", pRequest.Query, pRequest.MaxCases, tResp.Cases, 1)
		Set tResp.Available = 1
	} Catch ex {
		Set tResp = ##class(Readback.Msg.RetrievalResponse).%New()
		Set tResp.Available = 0, tResp.Reason = ..Redact("retrieval failed: "_ex.DisplayString())
	}
	Quit tResp
}

/// Runs one search and appends the items, best score first, equal scores by id, at most pMax, none below the minimum.
Method Collect(pTool As %String, pQuery As %String, pMax As %Integer, pList As %ListOfObjects, pIsCase As %Boolean)
{
	Quit:pMax<1
	Set tResult = ..Tools.ExecuteTool(pTool, {"query":(pQuery),"top_k":(pMax + 5)})
	If '$IsObject(tResult) || 'tResult.%IsDefined("value") || (tResult.%GetTypeOf("value") '= "array") {
		Throw ##class(%Exception.General).%New("SearchFailed", 5001, , "the "_pTool_" search returned no result list")
	}
	Set tHits = tResult.value
	For i = 0:1:tHits.%Size()-1 {
		Set tHit = tHits.%Get(i), tScore = tHit.score
		Continue:tScore<..#MinScore
		Set tId = $Select(pIsCase:+tHit.metadata.traceId, 1:tHit.metadata.passage)
		Set tKey = $Justify(1000000 - $Number(tScore * 1000000, 0), 8)_"|"_$Justify($Select(pIsCase:tId, 1:0), 12)_"|"_$Select(pIsCase:"", 1:tId)
		Set tSort(tKey) = i
	}
	Set tKey = "", tCount = 0
	For {
		Set tKey = $Order(tSort(tKey))
		Quit:tKey=""
		Quit:tCount>=pMax
		Set tHit = tHits.%Get(tSort(tKey)), tItem = ##class(Readback.Msg.RetrievalItem).%New()
		Set tCount = tCount + 1
		Set tItem.Score = tHit.score
		If pIsCase {
			Set tText = tHit.text, tItem.Id = "similar-case-"_tCount, tItem.TraceId = tHit.metadata.traceId
			Set tCut = $Find(tText, " Decision: ")
			Set tItem.Text = $Select(tCut>0:$Extract(tText, 1, tCut-12), 1:tText)
			Set tRest = $Select(tCut>0:$Extract(tText, tCut, *), 1:"")
			Set tItem.Decision = $Piece($Piece(tRest, ". Route: ", 1), ".", 1)
			Set tItem.Route = $Piece($Piece(tRest, ". Route: ", 2), ".", 1)
		} Else {
			Set tItem.Id = tHit.metadata.passage, tItem.Source = tHit.metadata.source, tItem.Title = tHit.metadata.title, tItem.Text = tHit.text
		}
		Do pList.Insert(tItem)
	}
}

/// A cheap view for the status endpoint: nothing is loaded and nothing is searched. Available means the model is in
/// the cache and the policy table holds the passages of the file it was built from.
ClassMethod Snapshot() As %DynamicObject
{
	Set tDir = $System.Util.GetEnviron("FASTEMBED_CACHE_DIR")
	Set tPassages = $Select(..CountRows(..#PolicyTable)<0:0, 1:..CountRows(..#PolicyTable)), tCases = $Select(..CountRows(..#CaseTable)<0:0, 1:..CountRows(..#CaseTable))
	Set tRes = {}
	Do tRes.%Set("available", ((tDir'="") && ..HasModel(tDir) && (tPassages>0)), "boolean")
	Set tRes.indexVersion = ##class(Readback.Retrieval.Policy).StoredVersion()
	Set tRes.passages = tPassages, tRes.confirmedCases = tCases
	Quit tRes
}

/// Builds the engine once at start-up so the policy index is ready before the first case. An engine that is
/// not available is reported, never fatal: cases then go to a person with the reason.
ClassMethod Prepare() As %Status
{
	Set tEngine = ..%New()
	Do tEngine.Build()
	Quit:tEngine.Available $$$OK
	Quit $System.Status.Error(5001, tEngine.Reason)
}

/// Prints two identical searches, for the offline check. Returns 1 when retrieval is available and both agree.
ClassMethod SelfCheck(pQuery As %String = "hemolyzed sample high potassium") As %Boolean
{
	Set tEngine = ..%New()
	Do tEngine.Build()
	Write "RB_SELF available=", tEngine.Available, " reason=", tEngine.Reason, !
	Quit:'tEngine.Available 0
	Set tReq = ##class(Readback.Msg.RetrievalRequest).%New()
	Set tReq.Query = pQuery
	Set tA = ..Signature(tEngine.Search(tReq)), tB = ..Signature(tEngine.Search(tReq))
	Write "RB_SELF first=", tA, !
	Write "RB_SELF second=", tB, !
	Write "RB_SELF identical=", (tA = tB), !
	Quit (tA = tB) && (tA '= "")
}

ClassMethod Signature(pResp As Readback.Msg.RetrievalResponse) As %String
{
	Quit:'pResp.Available ""
	Set tSig = ""
	For i = 1:1:pResp.Passages.Count() { Set tSig = tSig_pResp.Passages.GetAt(i).Id_":"_pResp.Passages.GetAt(i).Score_";" }
	Quit tSig
}

}
