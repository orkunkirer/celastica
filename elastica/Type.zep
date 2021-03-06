namespace Elastica;

/**
 * Elastica type object
 *
 * elasticsearch has for every types as a substructure. This object
 * represents a type inside a context
 * The hierarchy is as following: client -> index -> type -> document
 *
 * @package  Elastica
 * @author   Aris Kemper <aris.github@gmail.com>
 */
class Type implements SearchableInterface
{
    /**
     * Index
     *
     * @var \Elastica\Index Index object
     */
    protected _index = null;

    /**
    * Type name
    *
    * @var string Type name
    */
    protected _name = "";

    /**
     * @var array|string A callable that serializes an object passed to it
     */
    protected _serializer;

    /**
     * Creates a new type object inside the given index
     *
     * @param \Elastica\Index index Index Object
     * @param string name Type name
     */
    public function __construct(var index, string name) -> void
    {
        let this->_index = index;
        let this->_name = name;
    }

    /**
     * Returns the type name
     *
     * @return string Type name
     */
    public function getName() -> string
    {
        return this->_name;
    }

    /**
    * Returns index client
    *
    * @return \Elastica\Index Index object
    */
    public function getIndex()
    {
        return this->_index;
    }

    /**
    * Adds the given document to the search index
    *
    * @param  \Elastica\Document doc Document with data
    * @return \Elastica\Response
    */
    public function addDocument(var doc) -> <\Elastica\Response>
    {
        var path, type, options, response, data;

        let path = urlencode(doc->getId());
        let type = \Elastica\Request::PUT;

        // If id is empty, POST has to be used to automatically create id
        if empty path {
            let type = \Elastica\Request::POST;
        }

        let options = doc->getOptions(
            [
                "version",
                "version_type",
                "routing",
                "percolate",
                "parent",
                "ttl",
                "timestamp",
                "op_type",
                "consistency",
                "replication",
                "refresh",
                "timeout"
            ]
        );

        let response = this->request(path, type, doc->getData(), options);

        let data = response->getData();
        // set autogenerated id to document
        if doc->isAutoPopulate()
                || this->getIndex()->getClient()->getConfigValue(["document", "autoPopulate"], false)
            && response->isOk()
        {
            if !doc->hasId() {
                if isset data["_id"] {
                    doc->setId(data["_id"]);
                }
            }
            if isset data["_version"] {
                doc->setVersion(data["_version"]);
            }
        }

        return response;
    }

    /**
    * @param object
    * @param Document doc
    * @return Response
    * @throws Exception\RuntimeException
    */
    public function addObject(var obj, var doc = null)
    {
        var data;

        if !isset this->_serializer {
            throw new \Elastica\Exception\RuntimeException("No serializer defined");
        }

        let data = call_user_func(this->_serializer, obj);
        if !doc {
            let doc = new \Elastica\Document();
        }
        doc->setData(data);

        return this->addDocument(doc);
    }

    /**
    * Update document, using update script. Requires elasticsearch >= 0.19.0
    *
    * @param  \Elastica\Document|\Elastica\Script data Document with update data
    * @throws \Elastica\Exception\InvalidException
    * @return \Elastica\Response
    * @link http://www.elasticsearch.org/guide/reference/api/update.html
    */
    public function updateDocument(var data) -> <\Elastica\Response>
    {
        if !(data instanceof \Elastica\Document) && !(data instanceof \Elastica\Script) {
            throw new \InvalidArgumentException("Data should be a Document or Script");
        }

        if !data->hasId() {
            throw new \Elastica\Exception\InvalidException("Document or Script id is not set");
        }

        return this->getIndex()->getClient()->updateDocument(
            data->getId(),
            data,
            this->getIndex()->getName(),
            this->getName()
        );
    }

    /**
    * Get the document from search index
    *
    * @param  string id Document id
    * @param  array options Options for the get request.
    * @throws \Elastica\Exception\NotFoundException
    * @return \Elastica\Document
    */
    public function getDocument(var id, var options = []) -> <\Elastica\Document>
    {
        var data, path, response, result, info, document;

        let path = urlencode(id);

        try {
            let response = this->request(path, \Elastica\Request::GET, [], options);
            let result = response->getData();
        } catch \Elastica\Exception\ResponseException {
            throw new \Elastica\Exception\NotFoundException("doc id " . id . " not found");
        }

        let info = response->getTransferInfo();
        if info["http_code"] !== 200 {
            throw new \Elastica\Exception\NotFoundException("doc id " . id . " not found");
        }

        if isset result["fields"] {
            let data = result["fields"];
        } else {
            if isset result["_source"] {
                let data = result["_source"];
            } else {
                let data = [];
            }
        }

        let document = new \Elastica\Document(id, data, this->getName(), this->getIndex());
        document->setVersion(result["_version"]);

        return document;
    }


    /**
    * @param \Elastica\Document document
    * @return \Elastica\Response
    */
    public function deleteDocument(var document)
    {
        var options;

        let options = document->getOptions(
            [
                "version",
                "version_type",
                "routing",
                "parent",
                "replication",
                "consistency",
                "refresh",
                "timeout"
            ]
        );
        return this->deleteById(document->getId(), options);
    }

    /**
    * Uses _bulk to delete documents from the server
    *
    * @param  array|\Elastica\Document[] docs Array of Elastica\Document
    * @return \Elastica\Bulk\ResponseSet
    * @link http://www.elasticsearch.org/guide/reference/api/bulk.html
    */
    public function deleteDocuments(var docs)
    {
        return this->getIndex()->deleteDocuments(this->_setDocsType(docs));
    }

    /**
    * Deletes an entry by its unique identifier
    *
    * @param  int|string id Document id
    * @param array options
    * @throws \InvalidArgumentException
    * @throws \Elastica\Exception\NotFoundException
    * @return \Elastica\Response        Response object
    * @link http://www.elasticsearch.org/guide/reference/api/delete.html
    */
    public function deleteById(var id, var options = []) -> <\Elastica\Response>
    {
        var response, responseData;

        if empty id || !trim(id) {
            throw new \InvalidArgumentException();
        }

        let id = urlencode(id);
        let response = this->request(id, \Elastica\Request::DELETE, [], options);
        let responseData = response->getData();

        if isset responseData["found"] && false == responseData["found"] {
            throw new \Elastica\Exception\NotFoundException("Doc id " . id . " not found and can not be deleted");
        }

        return response;
    }

    /**
    * Deletes the given list of ids from this type
    *
    * @param  array ids
    * @return \Elastica\Response Response object
    */
    public function deleteIds(var ids) -> <\Elastica\Response>
    {
        return this->getIndex()->getClient()->deleteIds(ids, this->getIndex(), this);
    }


    /**
    * Deletes entries in the db based on a query
    *
    * @param  \Elastica\Query|string query Query object
    * @return \Elastica\Response
    * @link http://www.elasticsearch.org/guide/reference/api/delete-by-query.html
    */
    public function deleteByQuery(var query) -> <\Elastica\Response>
    {
        if typeof query == "string" {
            // query_string queries are not supported for delete by query operations
            return this->request("_query", \Elastica\Request::DELETE, [], ["q": query]);
        }
        let query = \Elastica\Query::create(query);

        return this->request("_query", \Elastica\Request::DELETE, query->getQuery());
    }

    /**
    * Deletes the index type.
    *
    * @return \Elastica\Response
    */
    public function delete() -> <\Elastica\Response>
    {
        var response;

        let response = this->request("", \Elastica\Request::DELETE);

        return response;
    }

    /**
    * More like this query based on the given object
    *
    * The id in the given object has to be set
    *
    * @param  \Elastica\Document doc Document to query for similar objects
    * @param  array params OPTIONAL Additional arguments for the query
    * @param  string|array|\Elastica\Query query OPTIONAL Query to filter the moreLikeThis results
    * @return \Elastica\ResultSet          ResultSet with all results inside
    * @link http://www.elasticsearch.org/guide/reference/api/more-like-this.html
    */
    public function moreLikeThis(<\Elastica\Document> doc, var params = [], var query = [])
    {
        var path, response;

        let path = doc->getId() . "/_mlt";
        let query = \Elastica\Query::create(query);
        let response = this->request(path, \Elastica\Request::GET, query->toArray(), params);

        return new \Elastica\ResultSet(response, query);
    }

    /**
    * Makes calls to the elasticsearch server based on this type
    *
    * @param  string path Path to call
    * @param  string method Rest method to use (GET, POST, DELETE, PUT)
    * @param  array data OPTIONAL Arguments as array
    * @param  array query OPTIONAL Query params
    * @return \Elastica\Response Response object
    */
    public function request(string path, string method, var data = [], var query = []) -> <\Elastica\Response>
    {
        var pathToCall;

        let pathToCall = this->getName() . "/" . path;

        return this->getIndex()->request(pathToCall, method, data, query);
    }

    /**
    * Sets the serializer callable used in addObject
    * @see \Elastica\Type::addObject
    *
    * @param array|string serializer @see \Elastica\Type::_serializer
    */
    public function setSerializer(serializer)
    {
        let this->_serializer = serializer;
    }

    /**
    * Checks if the given type exists in Index
    *
    * @return bool True if type exists
    */
    public function exists() -> boolean
    {
        var response, info;

        let response = this->getIndex()->request(this->getName(), \Elastica\Request::HEAD);
        let info = response->getTransferInfo();

        return info["http_code"] == 200;
    }

    /**
    * sets the docs type
    * @param docs
    */
    protected function _setDocsType(var docs) -> array
    {
        var doc;

        for doc in docs {
            doc->setType(this->getName());
        }
        return docs;
    }

    /**
    * Uses _bulk to send documents to the server
    *
    * @param  array|\Elastica\Document[] docs Array of Elastica\Document
    * @return \Elastica\Bulk\ResponseSet
    * @link http://www.elasticsearch.org/guide/reference/api/bulk.html
    */
    public function updateDocuments(var docs) -> <\Elastica\Bulk\ResponseSet>
    {
        return this->getIndex()->updateDocuments(this->_setDocsType(docs));
    }

    /**
     * Uses _bulk to send documents to the server
     *
     * @param  array|\Elastica\Document[] docs Array of Elastica\Document
     * @return \Elastica\Bulk\ResponseSet
     * @link http://www.elasticsearch.org/guide/reference/api/bulk.html
     */
    public function addDocuments(array docs) -> <\Elastica\Bulk\ResponseSet>
    {
        return this->getIndex()->addDocuments(this->_setDocsType(docs));
    }

    /**
    * Uses _bulk to send documents to the server
    *
    * @param objects[] objects
    * @return \Elastica\Bulk\ResponseSet
    * @link http://www.elasticsearch.org/guide/reference/api/bulk.html
    */
    public function addObjects(var objects) -> <\Elastica\Bulk\ResponseSet>
    {
        var docs = [], obj, doc, data;

        if !this->_serializer {
            throw new \Elastica\Exception\RuntimeException("No serializer defined");
        }

        for obj in objects {
            let data = call_user_func(this->_serializer, obj);
            let doc = new \Elastica\Document();
            doc->setData(data);
            doc->setType(this->getName());
            let docs[] = doc;
        }

        return this->getIndex()->addDocuments(docs);
    }

    /**
    * @param string id
    * @param array|string data
    * @return Document
    */
    public function createDocument(string id = "", var data = []) -> <\Elastica\Document>
    {
        var document;

        let document = new \Elastica\Document(id, data);
        document->setType(this);

        return document;
    }

    /**
    * Sets value type mapping for this type
    *
    * @param  \Elastica\Type\Mapping|array mapping Elastica\Type\MappingType object or property array with all mappings
    * @return \Elastica\Response
    */
    public function setMapping(var mapping) -> <\Elastica\Response>
    {
        let mapping = \Elastica\Type\Mapping::create(mapping);
        mapping->setType(this);

        return mapping->send();
    }

    /**
    * Returns current mapping for the given type
    *
    * @return array Current mapping
    */
    public function getMapping() -> array
    {
        var path = "_mapping", response, data;

        let response = this->request(path, \Elastica\Request::GET);
        let data = response->getData();
        if !isset data[this->getIndex()->getName()] {
            return [];
        }
        return data[this->getIndex()->getName()]["mappings"];
    }

     /**
    * Create search object
    *
    * @param  string|array|\Elastica\Query query Array with all query data inside or a Elastica\Query object
    * @param  int|array options OPTIONAL Limit or associative array of options (option=>value)
    * @return \Elastica\Search
    */
    public function createSearch(var query = "", var options = null) -> <\Elastica\Search>
    {
        var search;

        let search = new \Elastica\Search(this->getIndex()->getClient());
        search->addIndex(this->getIndex());
        search->addType(this);
        search->setOptionsAndQuery(options, query);

        return search;
    }

    /**
    * Do a search on this type
    *
    * @param  string|array|\Elastica\Query query Array with all query data inside or a Elastica\Query object
    * @param  int|array options OPTIONAL Limit or associative array of options (option=>value)
    * @return \Elastica\ResultSet          ResultSet with all results inside
    * @see \Elastica\SearchableInterface::search
    */
    public function search(var query = "", var options = null) -> <\Elastica\ResultSet>
    {
        var search;

        let search = this->createSearch(query, options);

        return search->search();
    }

    /**
    * Count docs by query
    *
    * @param  string|array|\Elastica\Query query Array with all query data inside or a Elastica\Query object
    * @return int                         number of documents matching the query
    * @see \Elastica\SearchableInterface::count
    */
    public function count(var query = "") -> int
    {
        var search;

        let search = this->createSearch(query);

        return search->count();
    }
}
